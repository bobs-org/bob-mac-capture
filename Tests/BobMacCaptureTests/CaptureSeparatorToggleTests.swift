import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureSeparatorToggleTests: XCTestCase {
    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags = [],
        keyCode: UInt16 = 41
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

    private func makeTextView(_ text: String) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    private func makeHostedTextView(_ text: String) -> (NSTextView, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let textView = makeTextView(text)
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        XCTAssertNotNil(textView.undoManager)
        return (textView, window)
    }

    private func wireNativeApply(_ model: CapturePanelModel, textView: NSTextView) {
        model.applyNativeRewriteEdit = { edit in
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: textView
            )
        }
    }

    private func typeSeparator(
        _ typed: String,
        into textView: NSTextView,
        model: CapturePanelModel
    ) {
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: typed, modifiers: typed == "|" ? .shift : []),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        let selection = textView.selectedRange()
        textView.insertText(typed, replacementRange: selection)
        model.plainDraft = textView.string
        let caretUTF16 = textView.selectedRange().location
        let caretUTF8 = utf8Offset(in: textView.string, utf16Offset: caretUTF16)
            ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
    }

    private func relationCandidate(from: Bool = false) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: from ? "~~tasks:source" : "~tasks:target",
            taskRef: from ? "2:bbbb2222" : "1:aaaa1111",
            blockID: from ? "source" : "target",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: from ? "Source" : "Target",
            group: "open",
            notePath: "tasks.md",
            locator: "tasks"
        )
    }

    private func installRelationPicker(
        on model: CapturePanelModel,
        from: Bool = false,
        draft: String? = nil
    ) {
        let direction: DependencyPickerDirection = from ? .linkedFrom : .linksTo
        model.installRelationPickerForPreviews(
            candidates: [relationCandidate(from: from)],
            draft: draft ?? (from ? "New task ~~" : "New task ~"),
            replacement: CaptureRange(start: 9, end: from ? 11 : 10),
            owner: DependencyOwner(kind: "new_task", text: "New task"),
            direction: direction
        )
    }

    private func processClient(
        recordURL: URL? = nil,
        extra: [String: String] = [:]
    ) throws -> BobProcessClient {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        if let recordURL {
            environment["FAKE_BOB_RECORD_PATH"] = recordURL.path
        }
        for (key, value) in extra {
            environment[key] = value
        }
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

    /// Whether the edit just handed to `model` went to Bob's rewrite lane.
    /// Every rewrite launch sets the model's rewrite task synchronously, so
    /// the answer is known right after the edit; a fixed sleep before
    /// reading the record lost the race on slow CI runners. A forwarded key
    /// must also reach fake-bob, so poll its record instead of sleeping.
    private func rewriteWasForwarded(
        model: CapturePanelModel,
        recordURL: URL,
        timeout: TimeInterval = 5
    ) async -> Bool {
        guard model.rewriteInFlightForTesting else {
            return false
        }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            if !nonCloseAliasRewriteCalls(in: record).isEmpty {
                return true
            }
            if Date() > deadline {
                return false
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func relationDashWasForwarded(
        text: String,
        modifiers: NSEvent.ModifierFlags = [],
        selection: NSRange? = nil,
        modalFieldActive: Bool = false
    ) async throws -> Bool {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        model.plainDraft = text
        let textView = makeTextView(text)
        if let selection {
            textView.setSelectedRange(selection)
        }
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "-", modifiers: modifiers),
            firstResponder: textView,
            model: model,
            modalFieldActive: modalFieldActive
        )
        textView.insertText("-", replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        let caretUTF8 = utf8Offset(
            in: textView.string,
            utf16Offset: textView.selectedRange().location
        ) ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
        return await rewriteWasForwarded(model: model, recordURL: recordURL)
    }

    private func relationEqualsWasForwarded(
        text: String,
        characters: String = "=",
        modifiers: NSEvent.ModifierFlags = [],
        selection: NSRange? = nil,
        modalFieldActive: Bool = false,
        parse: CaptureParseResponse? = nil
    ) async throws -> Bool {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        model.plainDraft = text
        model.latestParse = parse
        let textView = makeTextView(text)
        if let selection {
            textView.setSelectedRange(selection)
        }
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: characters, modifiers: modifiers),
            firstResponder: textView,
            model: model,
            modalFieldActive: modalFieldActive
        )
        textView.insertText(characters, replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        let caretUTF8 = utf8Offset(
            in: textView.string,
            utf16Offset: textView.selectedRange().location
        ) ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
        return await rewriteWasForwarded(model: model, recordURL: recordURL)
    }

    // MARK: - Intent

    func testIntentRecordsCollapsedColonAndCaret() {
        let model = CapturePanelModel()
        let textView = makeTextView("Do work @file:id")
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^"),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        textView.insertText("^", replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        XCTAssertEqual(model.plainDraft, "Do work @file:id^")
    }

    func testIntentDeclinesCommandControlOptionAndSelection() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel()
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file:id")
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^", modifiers: .command),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^", modifiers: .control),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^", modifiers: .option),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "+", modifiers: .command),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "+", modifiers: .control),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "+", modifiers: .option),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        for alias in [".", ";"] {
            CapturePanelController.noteSeparatorToggleIntentIfEligible(
                event: keyEvent(characters: alias, modifiers: .command),
                firstResponder: textView,
                model: model,
                modalFieldActive: false
            )
            CapturePanelController.noteSeparatorToggleIntentIfEligible(
                event: keyEvent(characters: alias, modifiers: .control),
                firstResponder: textView,
                model: model,
                modalFieldActive: false
            )
            CapturePanelController.noteSeparatorToggleIntentIfEligible(
                event: keyEvent(characters: alias, modifiers: .option),
                firstResponder: textView,
                model: model,
                modalFieldActive: false
            )
        }
        textView.setSelectedRange(NSRange(location: 0, length: 2))
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^"),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        for alias in [".", ";"] {
            CapturePanelController.noteSeparatorToggleIntentIfEligible(
                event: keyEvent(characters: alias),
                firstResponder: textView,
                model: model,
                modalFieldActive: false
            )
        }
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.insertText("+", replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotEqual(model.statusText, "Changed @file:id to @file+id")
        XCTAssertFalse(!nonCloseAliasRewriteCalls(in: try String(contentsOf: recordURL)).isEmpty)
    }

    func testIntentDeclinesModalFieldsAndMarkedText() {
        let model = CapturePanelModel()
        let textView = makeTextView("Do work @file:id")
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^"),
            firstResponder: textView,
            model: model,
            modalFieldActive: true
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "."),
            firstResponder: textView,
            model: model,
            modalFieldActive: true
        )
        textView.setMarkedText(
            "^",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: (textView.string as NSString).length, length: 0)
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^"),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "."),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: ";"),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        textView.unmarkText()
        model.plainDraft = "Do work @file:id^"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        XCTAssertNotEqual(model.statusText, "Changed @file:id to @file^id")
    }

    func testRelationDashIntentForwardsUngatedInTheMainEditor() async throws {
        let afterSpace = try await relationDashWasForwarded(text: "Fix it ")
        let afterTab = try await relationDashWasForwarded(text: "Fix it\t")
        let afterLetter = try await relationDashWasForwarded(text: "Fix itx")
        let command = try await relationDashWasForwarded(text: "Fix it ", modifiers: .command)
        let control = try await relationDashWasForwarded(text: "Fix it ", modifiers: .control)
        let option = try await relationDashWasForwarded(text: "Fix it ", modifiers: .option)
        let selection = try await relationDashWasForwarded(
            text: "Fix it ",
            selection: NSRange(location: 6, length: 1)
        )
        let modal = try await relationDashWasForwarded(
            text: "Fix it ",
            modalFieldActive: true
        )
        XCTAssertTrue(afterSpace)
        XCTAssertTrue(afterTab)
        // `-` is sent through Bob's rewrite lane in any main-editor context;
        // Bob decides whether it is a segment suffix or literal name text.
        XCTAssertTrue(afterLetter)
        XCTAssertFalse(command)
        XCTAssertFalse(control)
        XCTAssertFalse(option)
        XCTAssertFalse(selection)
        XCTAssertFalse(modal)
    }

    func testRelationEqualsIntentForwardsAtOpenerPositionsAndRelationEnds() async throws {
        let relation = "New task ~foo:bar"
        let relationParse = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            input: relation,
            body: relation,
            mode: "task",
            relationGrammar: 1,
            spans: [CaptureSpan(start: 14, end: 17, kind: "relation_block_id")]
        )
        let label = "New task ~foo:bar|see"
        let labelParse = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            input: label,
            body: label,
            mode: "task",
            relationGrammar: 1,
            spans: [CaptureSpan(start: 18, end: 21, kind: "relation_label")]
        )
        let afterTilde = try await relationEqualsWasForwarded(text: "New task ~")
        let afterSpace = try await relationEqualsWasForwarded(text: "New task ")
        let afterTab = try await relationEqualsWasForwarded(text: "New task\t")
        let afterRelation = try await relationEqualsWasForwarded(text: relation, parse: relationParse)
        let afterLabel = try await relationEqualsWasForwarded(text: label, parse: labelParse)
        let afterDash = try await relationEqualsWasForwarded(text: "Fix it -")
        let afterLetter = try await relationEqualsWasForwarded(text: "New task x")
        let lineStart = try await relationEqualsWasForwarded(text: "")
        let command = try await relationEqualsWasForwarded(text: "New task ~", modifiers: .command)
        let control = try await relationEqualsWasForwarded(text: "New task ~", modifiers: .control)
        let option = try await relationEqualsWasForwarded(text: "New task ~", modifiers: .option)
        let selection = try await relationEqualsWasForwarded(
            text: "New task ~",
            selection: NSRange(location: 9, length: 1)
        )
        let modal = try await relationEqualsWasForwarded(
            text: "New task ~",
            modalFieldActive: true
        )
        XCTAssertTrue(afterTilde)
        XCTAssertTrue(afterSpace)
        XCTAssertTrue(afterTab)
        XCTAssertTrue(afterRelation)
        XCTAssertTrue(afterLabel)
        XCTAssertFalse(afterDash)
        XCTAssertFalse(afterLetter)
        XCTAssertFalse(lineStart)
        XCTAssertFalse(command)
        XCTAssertFalse(control)
        XCTAssertFalse(option)
        XCTAssertFalse(selection)
        XCTAssertFalse(modal)
    }

    func testRelationTildeOnlyForwardsAtBobReportedRelationEnd() async throws {
        let text = "New task ~foo:bar"
        let parse = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            input: text,
            body: text,
            mode: "task",
            relationGrammar: 1,
            spans: [CaptureSpan(start: 14, end: 17, kind: "relation_block_id")]
        )
        let afterRelation = try await relationEqualsWasForwarded(
            text: text,
            characters: "~",
            parse: parse
        )
        let afterSpace = try await relationEqualsWasForwarded(
            text: "New task ",
            characters: "~"
        )
        let staleParse = try await relationEqualsWasForwarded(
            text: text,
            characters: "~",
            parse: CaptureParseResponse(
                ok: true,
                schemaVersion: 1,
                input: "stale draft",
                body: "stale draft",
                mode: "task",
                relationGrammar: 1,
                spans: [CaptureSpan(start: 0, end: 4, kind: "relation_block_id")]
            )
        )
        XCTAssertTrue(afterRelation)
        XCTAssertFalse(afterSpace)
        XCTAssertFalse(staleParse)
    }

    func testQuotedRelationLabelTokenEndIncludesClosingQuote() {
        let text = "Fix it ~foo:bar|\"see\""
        let parse = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            input: text,
            body: "Fix it",
            mode: "task",
            relationGrammar: 1,
            spans: [CaptureSpan(start: 17, end: 20, kind: "relation_label")]
        )
        XCTAssertTrue(CapturePanelController.relationTokenEndsAtCaret(
            text: text,
            caretUTF8: text.utf8.count,
            parse: parse
        ))

        let open = "Fix it ~foo:bar|\"see"
        let openParse = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            input: open,
            body: "Fix it",
            mode: "task",
            relationGrammar: 1,
            spans: [CaptureSpan(start: 17, end: 20, kind: "relation_label")]
        )
        XCTAssertFalse(CapturePanelController.relationTokenEndsAtCaret(
            text: open,
            caretUTF8: open.utf8.count,
            parse: openParse
        ))
    }

    // MARK: - Native apply

    func testCaretKeySwitchesColonMarkerThroughNativeInsert() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil {
            model.plainDraft == "Do work @file^id"
                && model.statusText == "Changed @file:id to @file^id"
        }

        XCTAssertEqual(textView.string, "Do work @file^id")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 16, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 16)
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 17 --format json -- Do work @file:id^"))
        XCTAssertFalse(record.contains("capture-complete --all-tasks --cursor 17"))
    }

    func testPlusKeySwitchesColonMarkerThroughNativeInsert() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("+", into: textView, model: model)
        await waitUntil {
            model.plainDraft == "Do work @file+id"
                && model.statusText == "Changed @file:id to @file+id"
        }

        XCTAssertEqual(textView.string, "Do work @file+id")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 16, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 16)
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        let expectedArgv =
            "argv=capture-rewrite --cursor 17 --format json -- " + "Do work @file:id+"
        XCTAssertTrue(record.contains(expectedArgv))
        XCTAssertFalse(record.contains("capture-complete --all-tasks --cursor 17"))
    }

    func testCommaKeySwitchesColonMarkerThroughNativeInsert() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator(",", into: textView, model: model)
        await waitUntil {
            model.plainDraft == "Do work @file+id"
                && model.statusText == "Changed @file:id to @file+id"
        }

        XCTAssertEqual(textView.string, "Do work @file+id")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 16, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 16)
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 17 --format json -- Do work @file:id,")
        )
        XCTAssertFalse(record.contains("capture-complete --all-tasks --cursor 17"))
    }

    func testColonAndCaretKeysSwitchPlusMarkerThroughNativeInsert() async throws {
        let colonModel = CapturePanelModel(debounceNanoseconds: 0)
        colonModel.processClient = try processClient()
        let colonView = makeTextView("Do work @file+id")
        wireNativeApply(colonModel, textView: colonView)

        typeSeparator(":", into: colonView, model: colonModel)
        await waitUntil {
            colonModel.plainDraft == "Do work @file:id"
                && colonModel.statusText == "Changed @file+id to @file:id"
        }
        XCTAssertEqual(colonView.string, "Do work @file:id")

        let caretModel = CapturePanelModel(debounceNanoseconds: 0)
        caretModel.processClient = try processClient()
        let caretView = makeTextView("Do work @file+id")
        wireNativeApply(caretModel, textView: caretView)

        typeSeparator("^", into: caretView, model: caretModel)
        await waitUntil {
            caretModel.plainDraft == "Do work @file^id"
                && caretModel.statusText == "Changed @file+id to @file^id"
        }
        XCTAssertEqual(caretView.string, "Do work @file^id")
    }

    func testDotKeySwitchesPlusMarkerToCaretThroughNativeInsert() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file+id")
        wireNativeApply(model, textView: textView)

        typeSeparator(".", into: textView, model: model)
        await waitUntil {
            model.plainDraft == "Do work @file^id"
                && model.statusText == "Changed @file+id to @file^id"
        }

        XCTAssertEqual(textView.string, "Do work @file^id")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 16, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 16)
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 17 --format json -- Do work @file+id.")
        )
        XCTAssertFalse(record.contains("capture-complete --all-tasks --cursor 17"))
    }

    func testColonKeySwitchesCaretMarkerThroughNativeInsert() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("Do work @file^id")
        wireNativeApply(model, textView: textView)

        typeSeparator(":", into: textView, model: model)
        await waitUntil {
            model.plainDraft == "Do work @file:id"
                && model.statusText == "Changed @file^id to @file:id"
        }

        XCTAssertEqual(textView.string, "Do work @file:id")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 16)
    }

    func testPickerAcceptedIDThenToggle() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("@file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.plainDraft == "@file^id" }

        XCTAssertEqual(textView.string, "@file^id")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 8)
        XCTAssertNil(model.picker)
    }

    func testPickerAcceptedIDThenPlusToggle() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("@file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("+", into: textView, model: model)
        await waitUntil { model.plainDraft == "@file+id" }

        XCTAssertEqual(textView.string, "@file+id")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 8)
        let record = try String(contentsOf: recordURL)
        let expectedArgv = "argv=capture-rewrite --cursor 9 --format json -- @file:id+"
        XCTAssertTrue(record.contains(expectedArgv))
        XCTAssertEqual(nonCloseAliasRewriteCalls(in: record).count, 1)
    }

    func testPlusAfterCaretIDSwitchesToSubBulletInOneUndoStep() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let (textView, window) = makeHostedTextView("Do work @file^id")
        defer { window.close() }
        wireNativeApply(model, textView: textView)

        typeSeparator("+", into: textView, model: model)
        await waitUntil {
            textView.string == "Do work @file+id"
                && model.statusText == "Changed @file^id to @file+id"
        }

        XCTAssertEqual(model.plainDraft, "Do work @file+id")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 16, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 16)
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        let expectedArgv =
            "argv=capture-rewrite --cursor 17 --format json -- " + "Do work @file^id+"
        XCTAssertTrue(record.contains(expectedArgv))

        // The swap is its own native undo step: one Undo restores the literal
        // post-key draft, and the restored text asks Bob for nothing more.
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Do work @file^id+")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(textView.string, "Do work @file^id+")
        let afterUndo = try String(contentsOf: recordURL)
        XCTAssertEqual(nonCloseAliasRewriteCalls(in: afterUndo).count, 1)
    }

    func testColonKeySwitchesSealedCaretMarkerThroughNativeInsert() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file^id@")
        wireNativeApply(model, textView: textView)

        typeSeparator(":", into: textView, model: model)
        await waitUntil {
            textView.string == "Do work @file:id@"
                && model.statusText == "Changed @file^id@ to @file:id@"
        }

        XCTAssertEqual(model.plainDraft, "Do work @file:id@")
        // The caret lands after the seal, where Bob put it.
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 17, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 17)
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 18 --format json -- Do work @file^id@:")
        )
    }

    func testCaretKeySwitchesSealedColonMarkerThroughNativeInsert() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file:id@")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil {
            textView.string == "Do work @file^id@"
                && model.statusText == "Changed @file:id@ to @file^id@"
        }

        XCTAssertEqual(model.plainDraft, "Do work @file^id@")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 17, length: 0))
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 18 --format json -- Do work @file:id@^")
        )
    }

    func testSealKeyAfterCaretIDOpensNothingAndSkipsRewrite() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file^id")
        wireNativeApply(model, textView: textView)

        typeSeparator("@", into: textView, model: model)
        // Wait for bob's parse of the sealed draft to paint the manila chip.
        await waitUntil {
            model.attributedDraft.runs.contains { $0.attributes.backgroundColor != nil }
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.plainDraft, "Do work @file^id@")
        XCTAssertEqual(textView.string, "Do work @file^id@")
        XCTAssertNil(model.picker)
        XCTAssertNil(model.completionResponse)
        XCTAssertFalse(model.completionVisible)
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(!nonCloseAliasRewriteCalls(in: record).isEmpty)
        XCTAssertFalse(record.contains("argv=capture-complete"))
    }

    func testPlusToggleUndoRestoresLiteralPostKeyDraftOnce() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let (textView, window) = makeHostedTextView("Do work @file:id")
        defer { window.close() }
        wireNativeApply(model, textView: textView)

        typeSeparator("+", into: textView, model: model)
        await waitUntil {
            textView.string == "Do work @file+id"
                && model.statusText == "Changed @file:id to @file+id"
        }

        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Do work @file:id+")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(textView.string, "Do work @file:id+")

        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(nonCloseAliasRewriteCalls(in: record).count, 1)
    }

    func testUnicodeDraftConvertsCursorToNativeRange() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("Hi 🧪 @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.plainDraft == "Hi 🧪 @file^id" }

        XCTAssertEqual(textView.string, "Hi 🧪 @file^id")
        let expectedUTF16 = ("Hi 🧪 @file^id" as NSString).length
        XCTAssertEqual(textView.selectedRange(), NSRange(location: expectedUTF16, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), "Hi 🧪 @file^id".utf8.count)
    }

    func testNativeUndoAndRedoDoNotRetriggerAssist() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        // Native undo lives on the window: a windowless text view has no
        // undo manager, so undo and redo would silently do nothing.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = makeTextView("Do work @file:id")
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 16, length: 0))
        XCTAssertNotNil(textView.undoManager)
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { textView.string == "Do work @file^id" }

        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Do work @file:id^")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(textView.string, "Do work @file:id^")

        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "Do work @file^id")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(textView.string, "Do work @file^id")
        // History stays intact: the swap undoes again, then the typed key.
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Do work @file:id^")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Do work @file:id")

        let record = try String(contentsOf: recordURL)
        let rewriteCount = nonCloseAliasRewriteCalls(in: record).count
        XCTAssertEqual(rewriteCount, 1)
    }

    func testSubsequentTypingAfterToggleDoesNotRetrigger() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.plainDraft == "Do work @file^id" }

        textView.insertText(" ", replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(model.plainDraft, "Do work @file^id ")
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(nonCloseAliasRewriteCalls(in: record).count, 1)
    }

    func testNoOpAndFailureLeaveLiteralText() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("hello")
        wireNativeApply(model, textView: textView)
        typeSeparator(":", into: textView, model: model)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.plainDraft, "hello:")
        XCTAssertEqual(textView.string, "hello:")

        let failing = CapturePanelModel(debounceNanoseconds: 0)
        failing.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_FAIL": "1"])
        let failingView = makeTextView("Do work @file:id")
        wireNativeApply(failing, textView: failingView)
        typeSeparator("^", into: failingView, model: failing)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(failing.plainDraft, "Do work @file:id^")
        XCTAssertEqual(failingView.string, "Do work @file:id^")
    }

    func testMalformedRangesDoNotMutateDraft() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_MALFORMED": "1"])
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)
        typeSeparator("^", into: textView, model: model)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.plainDraft, "Do work @file:id^")
        XCTAssertEqual(textView.string, "Do work @file:id^")
    }

    func testDelayedResponseIgnoredAfterEditCaretSubmitAndClientChange() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)
        typeSeparator("^", into: textView, model: model)

        model.plainDraft = "other"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        model.plainDraft = "Do work @file:id^"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(model.plainDraft, "Do work @file:id^")

        let caretModel = CapturePanelModel(debounceNanoseconds: 0)
        caretModel.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let caretView = makeTextView("Do work @file:id")
        wireNativeApply(caretModel, textView: caretView)
        typeSeparator("^", into: caretView, model: caretModel)
        caretModel.editorSelectionDidChange(cursorUTF8Offset: 0)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(caretModel.plainDraft, "Do work @file:id^")

        let submitModel = CapturePanelModel(debounceNanoseconds: 0)
        submitModel.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let submitView = makeTextView("Do work @file:id")
        wireNativeApply(submitModel, textView: submitView)
        typeSeparator("^", into: submitView, model: submitModel)
        submitModel.installCompatibleCaptureGrammarForTests()
        submitModel.submit(openAfterCapture: false)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotEqual(submitModel.statusText, "Changed @file:id to @file^id")

        let clientModel = CapturePanelModel(debounceNanoseconds: 0)
        clientModel.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let clientView = makeTextView("Do work @file:id")
        wireNativeApply(clientModel, textView: clientView)
        typeSeparator("^", into: clientView, model: clientModel)
        clientModel.setProcessClient(try processClient())
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(clientModel.plainDraft, "Do work @file:id^")

        let dismissModel = CapturePanelModel(debounceNanoseconds: 0)
        dismissModel.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let dismissView = makeTextView("Do work @file:id")
        wireNativeApply(dismissModel, textView: dismissView)
        typeSeparator("^", into: dismissView, model: dismissModel)
        dismissModel.prepareForDismissal()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(dismissModel.plainDraft, "Do work @file:id^")
    }

    // MARK: - Completion after an untoggled separator

    func testTypedColonAfterRouteOpensLinkPickerThroughKeyIntent() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("@file")
        wireNativeApply(model, textView: textView)

        typeSeparator(":", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        guard case .blockID = model.picker?.source else {
            XCTFail("expected a block-ID picker source")
            return
        }
        XCTAssertEqual(model.statusText, "Pick a task or type a new ID — press Tab to browse")
        XCTAssertEqual(model.plainDraft, "@file:")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 6 --format json -- @file:"))
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 6 --format json -- @file:"))
    }

    func testPeriodAliasAfterRouteOpensNewIDBlockPicker() async throws {
        let (textView, window) = makeHostedTextView("@file")
        defer { window.close() }
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        wireNativeApply(model, textView: textView)

        typeSeparator(".", into: textView, model: model)
        await waitUntil { textView.string == "@file^" && model.pickerVisible }

        XCTAssertEqual(model.plainDraft, "@file^")
        guard case .blockID(let context)? = model.picker?.source else {
            XCTFail("expected a Block ID picker")
            return
        }
        XCTAssertTrue(context.isNewIDMode)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 6 --format json -- @file.")
        )
        XCTAssertTrue(
            record.contains("capture-complete --all-tasks --cursor 6 --format json -- @file^")
        )
    }

    func testSemicolonAliasAfterRouteOpensLinkModeBlockPicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("@file")
        wireNativeApply(model, textView: textView)

        typeSeparator(";", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        XCTAssertEqual(model.plainDraft, "@file:")
        guard case .blockID(let context)? = model.picker?.source else {
            XCTFail("expected a Block ID picker")
            return
        }
        XCTAssertFalse(context.isNewIDMode)
        XCTAssertEqual(model.statusText, "Pick a task or type a new ID — press Tab to browse")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 6 --format json -- @file;")
        )
        XCTAssertTrue(
            record.contains("capture-complete --all-tasks --cursor 6 --format json -- @file:")
        )
    }

    func testSemicolonAliasAsWholeItemOpensTaskLinkPicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("")
        wireNativeApply(model, textView: textView)

        typeSeparator(";", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        XCTAssertEqual(model.plainDraft, ":")
        XCTAssertTrue(model.pickerSourceIsTaskLink)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 1 --format json -- ;"))
        XCTAssertTrue(record.contains("capture-complete --all-tasks --cursor 1 --format json -- :"))
    }

    func testNativeUndoRestoresLiteralSigilAliasWithoutRetriggering() async throws {
        let (textView, window) = makeHostedTextView("@file")
        defer { window.close() }
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        wireNativeApply(model, textView: textView)

        typeSeparator(".", into: textView, model: model)
        await waitUntil { textView.string == "@file^" && model.pickerVisible }
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "@file.")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        await waitUntil { !model.pickerVisible }

        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(nonCloseAliasRewriteCalls(in: record).count, 1)
        XCTAssertEqual(textView.string, "@file.")
    }

    func testUnchangedAliasReplyLeavesPeriodLiteralWithoutOpeningPicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Buy milk")
        wireNativeApply(model, textView: textView)

        typeSeparator(".", into: textView, model: model)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(model.plainDraft, "Buy milk.")
        XCTAssertEqual(textView.string, "Buy milk.")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(
            (try String(contentsOf: recordURL)).contains("capture-rewrite --cursor 9")
        )
    }

    // MARK: - Move-bullet sigil aliases

    func testPeriodAliasOnMoveBulletOpensMovePicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("@cash^goog-exit@\n- ")
        wireNativeApply(model, textView: textView)

        typeSeparator(".", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        XCTAssertEqual(model.plainDraft, "@cash^goog-exit@\n- ^")
        XCTAssertTrue(model.pickerSourceIsProjectTaskMove)
        guard case .projectTaskMove(let context)? = model.picker?.source else {
            XCTFail("expected a Move picker")
            return
        }
        XCTAssertEqual(context.scopeToken, "^")
        XCTAssertFalse(context.isLinkMove)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 20 --format json -- "))
        XCTAssertTrue(
            record.contains("capture-complete --all-tasks --cursor 20 --format json -- ")
        )
        XCTAssertTrue(record.contains("- ^"))
    }

    func testSemicolonAliasOnOfferMoveBulletOpensMoveAndLinkPicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("@cash:goog-exit@\n- ")
        wireNativeApply(model, textView: textView)

        typeSeparator(";", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        XCTAssertEqual(model.plainDraft, "@cash:goog-exit@\n- :")
        XCTAssertTrue(model.pickerSourceIsProjectTaskMove)
        guard case .projectTaskMove(let context)? = model.picker?.source else {
            XCTFail("expected a Move picker")
            return
        }
        XCTAssertEqual(context.scopeToken, ":")
        XCTAssertTrue(context.isLinkMove)
        XCTAssertEqual(context.pickerTitle, "Move & link into cash_goog_exit.md")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 20 --format json -- "))
        XCTAssertTrue(
            record.contains("capture-complete --all-tasks --cursor 20 --format json -- ")
        )
    }

    func testUndoAfterMoveAliasRestoresLiteralWithoutRetriggering() async throws {
        let (textView, window) = makeHostedTextView("@cash^goog-exit@\n- ")
        defer { window.close() }
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        wireNativeApply(model, textView: textView)

        typeSeparator(".", into: textView, model: model)
        await waitUntil { textView.string == "@cash^goog-exit@\n- ^" && model.pickerVisible }
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "@cash^goog-exit@\n- .")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        await waitUntil { !model.pickerVisible }

        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(nonCloseAliasRewriteCalls(in: record).count, 1)
        XCTAssertEqual(textView.string, "@cash^goog-exit@\n- .")
    }

    func testOlderBobMoveAliasReplyLeavesLiteralWithoutOpeningPicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_MOVE_UNCHANGED": "1"]
        )
        let textView = makeTextView("@cash^goog-exit@\n- ")
        wireNativeApply(model, textView: textView)

        typeSeparator(".", into: textView, model: model)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(model.plainDraft, "@cash^goog-exit@\n- .")
        XCTAssertEqual(textView.string, "@cash^goog-exit@\n- .")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(
            (try String(contentsOf: recordURL)).contains("capture-rewrite --cursor 20")
        )
    }

    func testDelayedAcceptedAliasSupersedesGatedCompletion() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.3"]
        )
        let textView = makeTextView("@file")
        wireNativeApply(model, textView: textView)

        typeSeparator(".", into: textView, model: model)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.pickerVisible)
        let early = (try? String(contentsOf: recordURL)) ?? ""
        XCTAssertFalse(early.contains("capture-complete"))

        await waitUntil { model.pickerVisible }
        XCTAssertEqual(model.plainDraft, "@file^")
    }

    func testTypedCaretAsWholeItemOpensActiveTaskPickerThroughKeyIntent() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        XCTAssertEqual(model.statusText, "Pick an active task — press Tab to browse")
    }

    func testTypedPlusAsWholeItemOpensParentTaskPickerThroughKeyIntent() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("")
        wireNativeApply(model, textView: textView)

        typeSeparator("+", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        XCTAssertTrue(model.pickerSourceIsParentTask)
        XCTAssertEqual(
            model.picker?.source.operatorContinuationHint,
            "Type a number or + to adjust; Esc to extend +5m"
        )
    }

    func testCompletionWaitsForRewriteThenOpensPicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.3"]
        )
        let textView = makeTextView("@file")
        wireNativeApply(model, textView: textView)

        typeSeparator(":", into: textView, model: model)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.pickerVisible)
        let early = (try? String(contentsOf: recordURL)) ?? ""
        XCTAssertFalse(early.contains("argv=capture-complete"))

        await waitUntil { model.pickerVisible }
        XCTAssertEqual(model.plainDraft, "@file:")
    }

    func testDelayedAcceptedToggleSupersedesGatedCompletion() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"]
        )
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.plainDraft == "Do work @file^id" }
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(model.plainDraft, "Do work @file^id")
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("capture-complete --all-tasks --cursor 17"))
    }

    func testNativeApplyDeclinesMarkedTextAndMissingEditor() {
        let textView = makeTextView("Do work @file:id^")
        textView.setMarkedText(
            "x",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 17, length: 0)
        )
        let edit = CaptureNativeRewriteEdit(
            replacementRange: NSRange(location: 8, length: 9),
            replacementText: "@file^id",
            resultingSelection: NSRange(location: 16, length: 0),
            expectedDraft: "Do work @file:id^",
            resultingDraft: "Do work @file^id"
        )
        XCTAssertFalse(
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: textView
            )
        )
        textView.unmarkText()
        XCTAssertFalse(
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: nil
            )
        )
    }

    func testWithoutNativeApplierLeavesLiteralToggleText() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        model.noteSeparatorToggleIntent(
            typed: "^",
            text: "Do work @file:id",
            selectedRange: NSRange(location: 16, length: 0)
        )
        model.plainDraft = "Do work @file:id^"
        model.editorTextDidChange(cursorUTF8Offset: 17)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.plainDraft, "Do work @file:id^")
    }

    func testTypedCommaInCloseTaskListStaysLiteralForCloseGrammar() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("x1")
        wireNativeApply(model, textView: textView)

        typeSeparator(",", into: textView, model: model)

        // Parse and rewrite run concurrently, so close-pending can show
        // before fake-bob records the rewrite. Wait for Bob's rewrite reply
        // too: the literal-comma checks below must see Bob's answer.
        XCTAssertTrue(model.rewriteInFlightForTesting)
        await waitUntil { model.isClosePending && !model.rewriteInFlightForTesting }
        XCTAssertEqual(model.plainDraft, "x1,")
        XCTAssertEqual(textView.string, "x1,")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 3 --format json -- x1,"))
        XCTAssertTrue(record.contains("capture-parse --format json -- x1,"))
    }

    func testCommaAfterCompleteTargetRunOpensNextParentPicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("@cash+goog-exit")
        wireNativeApply(model, textView: textView)

        typeSeparator(",", into: textView, model: model)

        await waitUntil { model.pickerSourceIsParentTask }
        XCTAssertEqual(model.plainDraft, "@cash+goog-exit +")
        XCTAssertEqual(textView.string, "@cash+goog-exit +")
        XCTAssertNil(model.completionResponse)
        guard case .parentTask(let context)? = model.picker?.source else {
            XCTFail("expected a parent-task picker")
            return
        }
        XCTAssertEqual(context.scope, .vault)
        XCTAssertEqual(context.scopeToken, "+")
        XCTAssertEqual(context.continuation, " +")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains(
                "argv=capture-rewrite --cursor 16 --format json -- @cash+goog-exit,"
            )
        )
        XCTAssertTrue(
            record.contains(
                "argv=capture-complete --all-tasks --cursor 17 --format json -- @cash+goog-exit +"
            )
        )
    }

    func testAcceptedRelationAndTypedPipeGluesAndOpensLabelCard() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        installRelationPicker(on: model)
        model.acceptPickerRow(id: "tasks.md|1:aaaa1111", submitAfterInsert: false)

        let textView = makeTextView(model.plainDraft)
        wireNativeApply(model, textView: textView)
        typeSeparator("|", into: textView, model: model)

        await waitUntil {
            model.relationLabelPromptVisible
                && model.plainDraft == "New task ~tasks:target|"
        }
        XCTAssertEqual(textView.string, "New task ~tasks:target|")
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linksTo)
        XCTAssertEqual(model.relationLabelPrompt?.targetText, "Target")
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 22, end: 23))
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 24 --format json -- New task ~tasks:target |"))
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 23 --format json -- New task ~tasks:target|"))
    }

    func testAcceptedLinkedFromAndTypedPipeOpensCardWithCorrectDirection() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        installRelationPicker(on: model, from: true)
        model.acceptPickerRow(id: "tasks.md|2:bbbb2222", submitAfterInsert: false)

        let textView = makeTextView(model.plainDraft)
        wireNativeApply(model, textView: textView)
        typeSeparator("|", into: textView, model: model)

        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.plainDraft, "New task ~~tasks:source|")
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linkedFrom)
        XCTAssertEqual(model.relationLabelSentence, "“Source” → “New task”")
    }

    func testPipeWithoutSpaceStillOpensCardAndRequestsCompletion() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("New task ~tasks:target")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|")
        XCTAssertEqual(textView.string, "New task ~tasks:target|")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 23 --format json -- New task ~tasks:target|"))
        XCTAssertTrue(record.contains("capture-complete --all-tasks --cursor 23"))
    }

    func testNativeUndoRestoresTheLiteralSpaceBeforePipe() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        installRelationPicker(on: model)
        model.acceptPickerRow(id: "tasks.md|1:aaaa1111", submitAfterInsert: false)
        let textView = makeTextView(model.plainDraft)
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { textView.string == "New task ~tasks:target|" }
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "New task ~tasks:target |")

        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(textView.string, "New task ~tasks:target |")
    }

    func testRelationLabelCommitPreservesFollowingRouteText() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("New task ~tasks:target @work")
        textView.setSelectedRange(NSRange(location: 22, length: 0))
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 22, end: 23))
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 9, end: 22))
        // Mid-draft caret must request completion at the pipe (23), not end of draft (29).
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains(
                "argv=capture-complete --all-tasks --cursor 23 --format json -- New task ~tasks:target| @work"
            ) == true
        }
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("capture-complete --all-tasks --cursor 29"))
        model.updateRelationLabelPromptLabel("follow")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "follow" }) == true
        }
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|follow @work")
    }

    func testShiftReturnLabelCommitPreservesFollowingTextMidDraft() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        installRelationPicker(on: model, draft: "New task ~ @work")
        model.openRelationLabelPromptFromPickerRow(id: "tasks.md|1:aaaa1111")

        XCTAssertTrue(model.relationLabelPromptVisible)
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 22, end: 22))
        await waitUntil { model.relationLabelPrompt?.catalogLoaded == true }
        model.updateRelationLabelPromptLabel("follow")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "follow" }) == true
        }
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|follow @work")
    }

    func testLeadingRelationPipeOpensWithNarrowRangeAndCommitsSee() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("~tasks:target Fix it")
        textView.setSelectedRange(NSRange(location: 13, length: 0))
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 0, end: 13))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 13, end: 14))
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linksTo)
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Fix it")
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains(
                "argv=capture-complete --all-tasks --cursor 14 --format json -- ~tasks:target| Fix it"
            ) == true
        }
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 14 --format json -- ~tasks:target| Fix it"))
        model.updateRelationLabelPromptLabel("see")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "see" }) == true
        }
        // The synthetic probe uses a larger replacement (13..25); the card must keep the narrow original.
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 13, end: 14))
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "~tasks:target|see Fix it")
    }

    func testDependencyTailCommitPreservesSuffixByteForByte() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Fix it ~tasks:target &tasks:source")
        textView.setSelectedRange(NSRange(location: 20, length: 0))
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 7, end: 20))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 20, end: 21))
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Fix it")
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains(
                "argv=capture-complete --all-tasks --cursor 21 --format json -- Fix it ~tasks:target| &tasks:source"
            ) == true
        }
        model.updateRelationLabelPromptLabel("see")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "see" }) == true
        }
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 20, end: 21))
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "Fix it ~tasks:target|see &tasks:source")
    }

    func testShiftReturnDependencyTailMidDraftPreservesSuffix() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        model.installRelationPickerForPreviews(
            candidates: [relationCandidate()],
            draft: "Fix it ~ &tasks:source",
            replacement: CaptureRange(start: 7, end: 8),
            owner: DependencyOwner(kind: "new_task", text: "Fix it"),
            direction: .linksTo
        )
        model.openRelationLabelPromptFromPickerRow(id: "tasks.md|1:aaaa1111")

        XCTAssertTrue(model.relationLabelPromptVisible)
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 7, end: 20))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 20, end: 20))
        await waitUntil { model.relationLabelPrompt?.catalogLoaded == true }
        model.updateRelationLabelPromptLabel("see")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "see" }) == true
        }
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "Fix it ~tasks:target|see &tasks:source")
    }

    func testQuotedNotePipeOpensWithEntireTokenRange() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("Fix ~\"My Note\":target")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 4, end: 21))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 21, end: 22))
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linksTo)
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Fix")
    }

    func testNonAsciiDraftPipeOpensAndConvertsCaret() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Hi 🧪 ~tasks:target")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 8, end: 21))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 21, end: 22))
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Hi 🧪")
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains(
                "argv=capture-complete --all-tasks --cursor 22 --format json -- Hi 🧪 ~tasks:target|"
            ) == true
        }
    }

    func testIncomingFromPipeOpensWithCorrectDirection() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("Fix ~~tasks:source")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 4, end: 18))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 18, end: 19))
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linkedFrom)
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Fix")
    }

    func testEmptyLabelReturnWithFollowingTailDropsOnlyPipeSuffix() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("New task ~tasks:target @work")
        textView.setSelectedRange(NSRange(location: 22, length: 0))
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 22, end: 23))
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target @work")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 22)
        XCTAssertEqual(model.statusText, "Inserted relation without a label")
    }

    func testEmptyLabelReturnDropsPipeAndLeavesBareRelation() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("New task ~tasks:target")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 22)
        XCTAssertEqual(model.statusText, "Inserted relation without a label")
    }

    func testOlderBobRelationLabelResponseUsesLegacyFallback() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(extra: ["FAKE_BOB_RELATION_OLD": "1"])
        let textView = makeTextView("New task ~tasks:target|")
        wireNativeApply(model, textView: textView)

        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        await waitUntil { model.relationLabelPromptVisible }

        XCTAssertEqual(model.relationLabelPrompt?.direction, .linksTo)
        XCTAssertNil(model.completionResponse)
    }

    // MARK: - Backslash hash alias

    func testBackslashAliasAfterTaskTypeOpensTypeMenuAndDoubleTapCloses() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_TASK_TYPE_CHOOSER": "1"]
        )
        let textView = makeTextView("jot idea ")
        wireNativeApply(model, textView: textView)

        typeSeparator("\\", into: textView, model: model)
        await waitUntil { model.completionVisible }

        XCTAssertEqual(model.plainDraft, "jot idea #")
        XCTAssertEqual(model.completionResponse?.context, "task_type")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 10 --format json -- jot idea \\"))
        XCTAssertTrue(record.contains("capture-complete --all-tasks --cursor 10 --format json -- jot idea #"))

        let completesBefore = record.components(separatedBy: "argv=capture-complete").count - 1
        guard let arm = model.hashAliasLiteralArm else {
            XCTFail("Expected a hash-alias arm after the alias rewrite")
            return
        }
        XCTAssertTrue(model.replaceHashAliasWithLiteralKey(arm))
        XCTAssertEqual(model.plainDraft, "jot idea \\")
        XCTAssertEqual(textView.string, "jot idea \\")
        XCTAssertFalse(model.completionVisible)
        try await Task.sleep(nanoseconds: 200_000_000)
        let after = try String(contentsOf: recordURL)
        XCTAssertEqual(after.components(separatedBy: "argv=capture-complete").count - 1, completesBefore)
        XCTAssertFalse(after.contains("capture-complete --all-tasks --cursor 10 --format json -- jot idea \\"))
    }

    func testBackslashAliasAfterSectionOpensSectionMenu() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("jot idea @foo")
        wireNativeApply(model, textView: textView)

        typeSeparator("\\", into: textView, model: model)
        await waitUntil { model.completionVisible }

        XCTAssertEqual(model.plainDraft, "jot idea @foo#")
        XCTAssertEqual(model.completionResponse?.context, "section")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 14 --format json -- jot idea @foo\\"))
    }

    func testBackslashAliasAfterDrawerOpensDrawerMenuAndDoubleTapCloses() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Postgres 17 minimum @foo+bar")
        wireNativeApply(model, textView: textView)

        typeSeparator("\\", into: textView, model: model)
        await waitUntil { model.completionVisible }

        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar#")
        XCTAssertEqual(model.completionResponse?.context, "drawer")
        guard let arm = model.hashAliasLiteralArm else {
            XCTFail("Expected a hash-alias arm after the alias rewrite")
            return
        }
        XCTAssertTrue(model.replaceHashAliasWithLiteralKey(arm))
        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar\\")
        XCTAssertFalse(model.completionVisible)
    }

    func testUndoAfterHashAliasRestoresLiteralWithoutRetriggering() async throws {
        let (textView, window) = makeHostedTextView("jot idea ")
        defer { window.close() }
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        wireNativeApply(model, textView: textView)

        typeSeparator("\\", into: textView, model: model)
        await waitUntil { textView.string == "jot idea #" && model.completionVisible }
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "jot idea \\")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        await waitUntil { !model.completionVisible }

        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(nonCloseAliasRewriteCalls(in: record).count, 1)
        XCTAssertEqual(textView.string, "jot idea \\")
    }

    func testOlderBobHashAliasReplyLeavesLiteralWithoutArming() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_HASH_UNCHANGED": "1"]
        )
        let textView = makeTextView("jot idea ")
        wireNativeApply(model, textView: textView)

        typeSeparator("\\", into: textView, model: model)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(model.plainDraft, "jot idea \\")
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.hashAliasLiteralArm)

        typeSeparator("\\", into: textView, model: model)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.plainDraft, "jot idea \\\\")
        XCTAssertNil(model.hashAliasLiteralArm)
    }

    func testDifferentKeyAfterHashAliasClearsArm() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("jot idea ")
        wireNativeApply(model, textView: textView)

        typeSeparator("\\", into: textView, model: model)
        await waitUntil { model.completionVisible }
        XCTAssertNotNil(model.hashAliasLiteralArm)

        _ = model.takeHashAliasLiteralArm()
        XCTAssertNil(model.hashAliasLiteralArm)
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(
                for: keyEvent(characters: "\\"),
                context: CaptureKeyRoutingContext()
            )
        )
    }

    // MARK: - Slash hash alias

    func testSlashAliasAfterTaskTypeOpensTypeMenuAndDoubleTapCloses() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_TASK_TYPE_CHOOSER": "1"]
        )
        let textView = makeTextView("jot idea ")
        wireNativeApply(model, textView: textView)

        typeSeparator("/", into: textView, model: model)
        await waitUntil { model.completionVisible }

        XCTAssertEqual(model.plainDraft, "jot idea #")
        XCTAssertEqual(model.completionResponse?.context, "task_type")
        XCTAssertEqual(model.hashAliasLiteralArm?.key, "/")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 10 --format json -- jot idea /"))
        XCTAssertTrue(record.contains("capture-complete --all-tasks --cursor 10 --format json -- jot idea #"))

        let completesBefore = record.components(separatedBy: "argv=capture-complete").count - 1
        guard let arm = model.hashAliasLiteralArm else {
            XCTFail("Expected a hash-alias arm after the slash alias rewrite")
            return
        }
        XCTAssertTrue(model.replaceHashAliasWithLiteralKey(arm))
        XCTAssertEqual(model.plainDraft, "jot idea /")
        XCTAssertEqual(textView.string, "jot idea /")
        XCTAssertFalse(model.completionVisible)
        try await Task.sleep(nanoseconds: 200_000_000)
        let after = try String(contentsOf: recordURL)
        XCTAssertEqual(after.components(separatedBy: "argv=capture-complete").count - 1, completesBefore)
        XCTAssertFalse(after.contains("capture-complete --all-tasks --cursor 10 --format json -- jot idea /"))
    }

    func testSlashAliasAfterSectionOpensSectionMenu() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("jot idea @foo")
        wireNativeApply(model, textView: textView)

        typeSeparator("/", into: textView, model: model)
        await waitUntil { model.completionVisible }

        XCTAssertEqual(model.plainDraft, "jot idea @foo#")
        XCTAssertEqual(model.completionResponse?.context, "section")
        XCTAssertEqual(model.hashAliasLiteralArm?.key, "/")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 14 --format json -- jot idea @foo/"))
    }

    func testSlashAliasAfterDrawerOpensDrawerMenuAndDoubleTapCloses() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Postgres 17 minimum @foo+bar")
        wireNativeApply(model, textView: textView)

        typeSeparator("/", into: textView, model: model)
        await waitUntil { model.completionVisible }

        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar#")
        XCTAssertEqual(model.completionResponse?.context, "drawer")
        XCTAssertEqual(model.hashAliasLiteralArm?.key, "/")
        guard let arm = model.hashAliasLiteralArm else {
            XCTFail("Expected a hash-alias arm after the slash alias rewrite")
            return
        }
        XCTAssertTrue(model.replaceHashAliasWithLiteralKey(arm))
        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar/")
        XCTAssertFalse(model.completionVisible)
    }

    func testUndoAfterSlashAliasRestoresLiteralWithoutRetriggering() async throws {
        let (textView, window) = makeHostedTextView("jot idea ")
        defer { window.close() }
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        wireNativeApply(model, textView: textView)

        typeSeparator("/", into: textView, model: model)
        await waitUntil { textView.string == "jot idea #" && model.completionVisible }
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "jot idea /")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        await waitUntil { !model.completionVisible }

        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(nonCloseAliasRewriteCalls(in: record).count, 1)
        XCTAssertEqual(textView.string, "jot idea /")
    }

    func testOlderBobSlashAliasReplyLeavesLiteralWithoutArming() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_HASH_UNCHANGED": "1"]
        )
        let textView = makeTextView("jot idea ")
        wireNativeApply(model, textView: textView)

        typeSeparator("/", into: textView, model: model)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(model.plainDraft, "jot idea /")
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.hashAliasLiteralArm)

        typeSeparator("/", into: textView, model: model)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.plainDraft, "jot idea //")
        XCTAssertNil(model.hashAliasLiteralArm)
    }

    func testBlankDraftSlashRecordsNoRewriteAndOpensGoto() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("")
        wireNativeApply(model, textView: textView)

        typeSeparator("/", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        XCTAssertTrue(model.pickerSourceIsTaskGoto)
        XCTAssertEqual(model.plainDraft, "/")
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(!nonCloseAliasRewriteCalls(in: record).isEmpty)
    }

    // MARK: - Close-outcome x/s aliases

    private func typeCloseAlias(
        _ typed: String,
        into textView: NSTextView,
        model: CapturePanelModel,
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: typed,
            charactersIgnoringModifiers: typed,
            isARepeat: isRepeat,
            keyCode: typed == "x" ? 7 : 1
        )!
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: event,
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        let selection = textView.selectedRange()
        textView.insertText(typed, replacementRange: selection)
        model.plainDraft = textView.string
        let caretUTF8 = utf8Offset(
            in: textView.string,
            utf16Offset: textView.selectedRange().location
        ) ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
    }

    private func makeSupportedModel(recordURL: URL? = nil) throws -> CapturePanelModel {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        if let recordURL {
            model.processClient = try processClient(recordURL: recordURL)
        } else {
            model.processClient = try processClient()
        }
        model.installCloseAliasSupportForTests(supported: true)
        return model
    }

    func testCloseAliasPrefilterTable() {
        // Fires rows must pass the lexical send filter.
        let fires = [
            "xx", "xs", "x1x", "x1s", "x!s", "x*x", "x*1x", "x@1s", "x1~2s",
            "x=1=s", "x=1=x", "x==s", "x=fix=s", "x=1!=x", "x=1=1s", "+2 xs",
            "@r:id=xx", "^r:id=x1s", "Fix it @r:id=xs", "Plan\n\nxx", "Hi 🧪\n\nxx",
            "2xx", "12xs", "--1 2xx", "^r:id=2xs", "Plan 2xx", "x made 2xx",
        ]
        for draft in fires {
            let before = String(draft.dropLast())
            XCTAssertTrue(
                CapturePanelController.closeAliasPrefilterAllows(
                    text: before, caretUTF8: before.utf8.count
                ),
                "prefilter should allow \(draft.debugDescription)"
            )
        }
        for prefix in ["2x", "02x", "@r:id=2x", "+2 2x"] {
            XCTAssertTrue(
                CapturePanelController.closeAliasPrefilterAllows(
                    text: prefix, caretUTF8: prefix.utf8.count
                ),
                "sized close prefix should reach Bob: \(prefix)"
            )
        }
        XCTAssertFalse(
            CapturePanelController.closeAliasPrefilterAllows(text: "100x", caretUTF8: 4),
            "three-digit prose remains outside the sized-close prefilter"
        )
        // Clear non-slots are blocked without spawning Bob.
        XCTAssertFalse(CapturePanelController.closeAliasPrefilterAllows(text: "ta", caretUTF8: 2))
        XCTAssertFalse(CapturePanelController.closeAliasPrefilterAllows(text: "X", caretUTF8: 1))
        XCTAssertFalse(CapturePanelController.closeAliasPrefilterAllows(text: "", caretUTF8: 0))
        XCTAssertFalse(CapturePanelController.closeAliasPrefilterAllows(text: "Plan", caretUTF8: 4))
        // Uppercase opener never forwards: previous char `X` is not adjacent.
        XCTAssertFalse(CapturePanelController.closeAliasPrefilterAllows(text: "X", caretUTF8: 1))
        XCTAssertFalse(CapturePanelController.closeAliasPrefilterAllows(text: "@r:id=X", caretUTF8: 7))
    }

    func testCloseAliasForwardsWholePastLinkLeadAndNumbered() async throws {
        let cases: [(before: String, typed: String, expected: String, summary: String, record: String)] = [
            ("x", "x", "x!", "Typed ! for x", "argv=capture-rewrite --cursor 2 --format json -- xx"),
            ("x", "s", "x*", "Typed * for s", "argv=capture-rewrite --cursor 2 --format json -- xs"),
            ("x=1=", "s", "x=1=*", "Typed * for s", "argv=capture-rewrite --cursor 5 --format json -- x=1=s"),
            ("@r:id=x", "x", "@r:id=x!", "Typed ! for x", "argv=capture-rewrite --cursor 8 --format json -- @r:id=xx"),
            ("+2 x", "s", "+2 x*", "Typed * for s", "argv=capture-rewrite --cursor 5 --format json -- +2 xs"),
            ("x1", "s", "x1*", "Typed * for s", "argv=capture-rewrite --cursor 3 --format json -- x1s"),
            ("2x", "x", "2x!", "Typed ! for x", "argv=capture-rewrite --cursor 3 --format json -- 2xx"),
            ("12x", "s", "12x*", "Typed * for s", "argv=capture-rewrite --cursor 4 --format json -- 12xs"),
            ("--1 2x", "x", "--1 2x!", "Typed ! for x", "argv=capture-rewrite --cursor 7 --format json -- --1 2xx"),
            ("^r:id=2x", "s", "^r:id=2x*", "Typed * for s", "argv=capture-rewrite --cursor 9 --format json -- ^r:id=2xs"),
        ]
        for (before, typed, expected, summary, record) in cases {
            let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let model = try makeSupportedModel(recordURL: recordURL)
            let textView = makeTextView(before)
            wireNativeApply(model, textView: textView)
            typeCloseAlias(typed, into: textView, model: model)
            await waitUntil { model.plainDraft == expected && model.statusText == summary }
            XCTAssertEqual(textView.string, expected, "before=\(before) typed=\(typed)")
            let logged = try String(contentsOf: recordURL)
            XCTAssertTrue(logged.contains(record), "missing \(record) in \(logged)")
        }
    }

    func testCloseAliasLeavesProseLiteral() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = try makeSupportedModel(recordURL: recordURL)
        let textView = makeTextView("Plan x")
        wireNativeApply(model, textView: textView)
        typeCloseAlias("s", into: textView, model: model)
        await waitUntil { !model.rewriteInFlightForTesting }
        XCTAssertEqual(model.plainDraft, "Plan xs")
        XCTAssertEqual(textView.string, "Plan xs")
        let logged = try String(contentsOf: recordURL)
        XCTAssertTrue(logged.contains("argv=capture-rewrite --cursor 7 --format json -- Plan xs"))
    }

    func testSizedCloseAliasLeavesProseLiteral() async throws {
        for (before, typed, expected, record) in [
            ("Plan 2x", "x", "Plan 2xx", "argv=capture-rewrite --cursor 8 --format json -- Plan 2xx"),
            ("x made 2x", "x", "x made 2xx", "argv=capture-rewrite --cursor 10 --format json -- x made 2xx"),
        ] as [(String, String, String, String)] {
            let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let model = try makeSupportedModel(recordURL: recordURL)
            let textView = makeTextView(before)
            wireNativeApply(model, textView: textView)
            typeCloseAlias(typed, into: textView, model: model)
            await waitUntil { !model.rewriteInFlightForTesting }
            XCTAssertEqual(model.plainDraft, expected, "before=\(before)")
            XCTAssertEqual(textView.string, expected, "before=\(before)")
            let logged = try String(contentsOf: recordURL)
            XCTAssertTrue(logged.contains(record), "missing \(record) in \(logged)")
        }

        // Uppercase `X` is not a close opener: the prefilter never spawns Bob.
        do {
            let recordURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let model = try makeSupportedModel(recordURL: recordURL)
            let textView = makeTextView("2X")
            wireNativeApply(model, textView: textView)
            typeCloseAlias("x", into: textView, model: model)
            XCTAssertFalse(model.rewriteInFlightForTesting)
            XCTAssertEqual(model.plainDraft, "2Xx")
            XCTAssertEqual(textView.string, "2Xx")
            let logged = (try? String(contentsOf: recordURL)) ?? ""
            XCTAssertFalse(
                logged.contains("capture-rewrite"),
                "uppercase X must not reach Bob: \(logged)"
            )
        }
    }

    func testCloseAliasDeclinesRepeatsModifiersUppercaseAndIME() async throws {
        // Repeats never alias.
        do {
            let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let model = try makeSupportedModel(recordURL: recordURL)
            let textView = makeTextView("x")
            wireNativeApply(model, textView: textView)
            typeCloseAlias("x", into: textView, model: model, isRepeat: true)
            XCTAssertFalse(model.rewriteInFlightForTesting)
            XCTAssertEqual(model.plainDraft, "xx")

        }
        // Command, Control, and Option never alias.
        for modifiers in [NSEvent.ModifierFlags.command, .control, .option] {
            let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let model = try makeSupportedModel(recordURL: recordURL)
            let textView = makeTextView("x")
            wireNativeApply(model, textView: textView)
            typeCloseAlias("x", into: textView, model: model, modifiers: modifiers)
            XCTAssertFalse(model.rewriteInFlightForTesting)
            XCTAssertEqual(model.plainDraft, "xx")

        }
        // Uppercase never aliases.
        do {
            let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let model = try makeSupportedModel(recordURL: recordURL)
            let textView = makeTextView("x")
            wireNativeApply(model, textView: textView)
            typeCloseAlias("X", into: textView, model: model)
            XCTAssertFalse(model.rewriteInFlightForTesting)
            XCTAssertEqual(model.plainDraft, "xX")

        }
        // Marked text never aliases.
        do {
            let model = try makeSupportedModel()
            let textView = makeTextView("x")
            textView.setMarkedText(
                "x",
                selectedRange: NSRange(location: 0, length: 1),
                replacementRange: NSRange(location: 1, length: 0)
            )
            CapturePanelController.noteSeparatorToggleIntentIfEligible(
                event: keyEvent(characters: "x"),
                firstResponder: textView,
                model: model,
                modalFieldActive: false
            )
            textView.unmarkText()
            model.plainDraft = "xx"
            model.editorTextDidChange(cursorUTF8Offset: 2)
            XCTAssertNotEqual(model.statusText, "Typed ! for x")
        }
        // Non-collapsed selections and modal fields never alias.
        do {
            let model = try makeSupportedModel()
            let textView = makeTextView("x")
            textView.setSelectedRange(NSRange(location: 0, length: 1))
            CapturePanelController.noteSeparatorToggleIntentIfEligible(
                event: keyEvent(characters: "x"),
                firstResponder: textView,
                model: model,
                modalFieldActive: false
            )
            CapturePanelController.noteSeparatorToggleIntentIfEligible(
                event: keyEvent(characters: "x"),
                firstResponder: makeTextView("x"),
                model: model,
                modalFieldActive: true
            )
            XCTAssertFalse(model.rewriteInFlightForTesting)
        }
    }

    func testCloseAliasUndoRestoresLiteralInOneStep() async throws {
        let model = try makeSupportedModel()
        let (textView, window) = makeHostedTextView("x")
        defer { window.orderOut(nil) }
        wireNativeApply(model, textView: textView)
        typeCloseAlias("x", into: textView, model: model)
        await waitUntil { model.plainDraft == "x!" }
        XCTAssertEqual(textView.string, "x!")
        textView.undoManager?.undo()
        // Undo restores the literal post-key draft; the model mirrors AppKit.
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        XCTAssertEqual(textView.string, "xx")
        textView.undoManager?.redo()
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        await waitUntil { model.plainDraft == "x!" }
        XCTAssertEqual(textView.string, "x!")
    }

    func testCloseAliasEmojiDraftConvertsCaret() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = try makeSupportedModel(recordURL: recordURL)
        let textView = makeTextView("Hi 🧪\n\nx")
        wireNativeApply(model, textView: textView)
        typeCloseAlias("x", into: textView, model: model)
        await waitUntil { model.plainDraft == "Hi 🧪\n\nx!" }
        XCTAssertEqual(textView.string, "Hi 🧪\n\nx!")
        let logged = try String(contentsOf: recordURL)
        XCTAssertTrue(logged.contains("argv=capture-rewrite --cursor"))
    }

    func testCloseAliasOldBobProbeBlocksAndWarnsOnce() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_CLOSE_UNCHANGED": "1"]
        )
        await model.awaitCloseAliasProbeForTests()
        XCTAssertFalse(model.closeAliasForwardingAllowed())
        let textView = makeTextView("x")
        wireNativeApply(model, textView: textView)
        typeCloseAlias("x", into: textView, model: model)
        XCTAssertFalse(model.rewriteInFlightForTesting)
        XCTAssertEqual(model.plainDraft, "xx")
        XCTAssertEqual(model.statusText, CapturePanelModel.closeAliasOldBobMessage)
        XCTAssertTrue(model.closeAliasAnnouncedForTests())
        let logged = try String(contentsOf: recordURL)
        XCTAssertTrue(logged.contains("argv=capture-rewrite --cursor 2 --format json -- xx"))
        let xxRewrites = logged.components(separatedBy: "argv=capture-rewrite --cursor 2 --format json -- xx").count - 1
        XCTAssertEqual(xxRewrites, 1, "blocked x/s must not spawn a rewrite; only the probe runs")
        // Second blocked key does not repeat the status.
        model.statusText = ""
        let secondView = makeTextView("x")
        wireNativeApply(model, textView: secondView)
        // Reuse the same model identity so the warning stays one-time.
        typeCloseAlias("s", into: secondView, model: model)
        XCTAssertFalse(model.rewriteInFlightForTesting)
        XCTAssertEqual(secondView.string, "xs")
        XCTAssertEqual(model.statusText, "")
    }

    func testCloseAliasUnknownBobStaysLiteralSilently() throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        // No client means no support and no warning.
        XCTAssertFalse(model.closeAliasForwardingAllowed())
        model.noteCloseAliasBlocked()
        XCTAssertEqual(model.statusText, "")
    }

}
