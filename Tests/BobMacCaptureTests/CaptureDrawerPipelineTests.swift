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

    private func drawerTitleNewlineEvent(_ key: String) -> NSEvent {
        switch key {
        case "Shift-Return":
            return keyEvent(keyCode: 36, characters: "\r", modifiers: .shift)
        case "Option-Return":
            return keyEvent(keyCode: 36, characters: "\r", modifiers: .option)
        case "Ctrl-J":
            return keyEvent(keyCode: 38, characters: "j", modifiers: .control)
        default:
            XCTFail("Unknown drawer newline key: \(key)")
            return keyEvent(keyCode: 0, characters: "")
        }
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

    private func drawerParseFixtureURL(
        draft: String,
        title: String?
    ) throws -> URL {
        var spans: [CaptureSpan] = []
        if let title, let range = draft.range(of: title) {
            let start = draft[..<range.lowerBound].utf8.count
            let end = start + title.utf8.count
            spans = [
                CaptureSpan(start: start - 2, end: start, kind: "drawer_marker"),
                CaptureSpan(
                    start: start,
                    end: end,
                    kind: "drawer_bullet",
                    key: title.uppercased(),
                    title: title
                ),
                CaptureSpan(start: end, end: end + 2, kind: "drawer_marker"),
            ]
        }
        let parse = CaptureParseResponse(
            ok: true,
            schemaVersion: 1,
            grammar: 33,
            input: draft,
            body: "",
            mode: "task",
            spans: spans
        )
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("drawer-title-parse-\(UUID().uuidString).json")
        try JSONEncoder().encode(parse).write(to: fixtureURL)
        return fixtureURL
    }

    private func openParsedDrawerTitle(
        _ draft: String,
        title: String
    ) async throws -> (
        CapturePanelModel, CapturePanelController, NSTextView, NSPanel, URL, URL, Int
    ) {
        let fixtureURL = try drawerParseFixtureURL(draft: draft, title: title)
        let (model, controller, textView, panel, recordURL) = try openDrawerDraft(
            draft,
            extra: ["FAKE_BOB_PARSE_FIXTURE": fixtureURL.path]
        )
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.latestParse?.input == draft }
        let titleRange = draft.range(of: title)!
        let titleEnd = titleRange.upperBound
        let caretUTF8 = draft[..<titleEnd].utf8.count
        let caretUTF16 = NSMaxRange(NSRange(titleRange, in: draft))
        textView.setSelectedRange(NSRange(location: caretUTF16, length: 0))
        model.editorSelectionDidChange(cursorUTF8Offset: caretUTF8)
        return (model, controller, textView, panel, recordURL, fixtureURL, caretUTF8)
    }

    private func openExpandedDrawerTitle(
        _ title: String
    ) async throws -> (CapturePanelModel, CapturePanelController, NSTextView, NSPanel, URL) {
        let (model, controller, textView, panel, recordURL) = try openDrawerDraft(
            "Prepare release\n- ",
            extra: ["FAKE_BOB_PARSE_EXIT": "1"]
        )
        XCTAssertNotNil(typeKey(starEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "Prepare release\n- ****" }
        for character in title {
            let event = keyEvent(keyCode: 0, characters: String(character))
            XCTAssertNotNil(typeKey(event, into: textView, model: model, controller: controller))
        }
        XCTAssertEqual(textView.string, "Prepare release\n- **\(title)**")
        // Close the title-typing undo group so the nested newline assist is
        // one undoable edit. Real typing has runloop gaps that naturally break
        // coalescing; the synchronous test loop does not. Yield a runloop
        // turn for the same boundary; otherwise title and newline coalesce
        // into one group (see CaptureListPanelTests).
        textView.breakUndoCoalescing()
        try? await Task.sleep(nanoseconds: 80_000_000)
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
        let (model, controller, textView, panel, _) = try openDrawerDraft("Prepare release\n- ")
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
            await waitUntil { textView.string == draft + "****" }
            XCTAssertEqual(
                textView.selectedRange(),
                NSRange(location: caretBetweenPairs(textView), length: 0)
            )
            XCTAssertTrue(model.plainDraft.hasSuffix("****"))
        }
    }

    func testQueuedStarIsAbsorbedOnce() async throws {
        let (model, controller, textView, panel, _) = try openDrawerDraft("Prepare release\n- ")
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
        XCTAssertEqual(textView.string, "Prepare release\n- *****")
    }

    func testBackspaceDeletesSkeletonViaExpansionArm() async throws {
        let (model, controller, textView, panel, _) = try openDrawerDraft("Prepare release\n- ")
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

    func testFreshDrawerSpansAuthorizeEachNestedNewlineKeyAndUndo() async throws {
        let draft = "Prepare release\n  - **Release Notes**"
        let expected = "Prepare release\n  - **Release Notes**\n    - "
        for key in ["Shift-Return", "Option-Return", "Ctrl-J"] {
            let (model, controller, textView, panel, _, fixtureURL, _) =
                try await openParsedDrawerTitle(draft, title: "Release Notes")
            defer { try? FileManager.default.removeItem(at: fixtureURL) }
            defer { panel.orderOut(nil) }

            XCTAssertNil(controller.routeKeyDown(drawerTitleNewlineEvent(key)), key)
            XCTAssertEqual(textView.string, expected, key)
            XCTAssertEqual(
                textView.selectedRange(),
                NSRange(location: (expected as NSString).length, length: 0),
                key
            )
            textView.undoManager?.undo()
            XCTAssertEqual(textView.string, draft, "\(key) is one undoable edit")
            XCTAssertNil(model.completionResponse)
        }
    }

    func testExpansionSessionAuthorizesEachNestedNewlineKey() async throws {
        let expected = "Prepare release\n- **Release Notes**\n  - "
        for key in ["Shift-Return", "Option-Return", "Ctrl-J"] {
            let (model, controller, textView, panel, _) =
                try await openExpandedDrawerTitle("Release Notes")
            defer { panel.orderOut(nil) }

            XCTAssertNil(controller.routeKeyDown(drawerTitleNewlineEvent(key)), key)
            XCTAssertEqual(textView.string, expected, key)
            XCTAssertEqual(
                textView.selectedRange(),
                NSRange(location: (expected as NSString).length, length: 0),
                key
            )
            textView.undoManager?.undo()
            XCTAssertEqual(textView.string, "Prepare release\n- **Release Notes**", key)
            XCTAssertNil(model.latestParse)
        }
    }

    func testFreshDrawerSpansAndExpansionSessionAuthorizeStarOvertype() async throws {
        let draft = "Prepare release\n  - **Release Notes**"
        let (model, controller, textView, panel, recordURL, fixtureURL, caretUTF8) =
            try await openParsedDrawerTitle(draft, title: "Release Notes")
        defer { panel.orderOut(nil) }
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        XCTAssertNil(controller.routeKeyDown(starEvent()))
        XCTAssertEqual(textView.string, draft)
        XCTAssertEqual(
            textView.selectedRange(), NSRange(location: (draft as NSString).length, length: 0))
        let overtypeRecord = (try? String(contentsOf: recordURL)) ?? ""
        XCTAssertTrue(
            overtypeRecord.components(separatedBy: "argv=capture-rewrite").dropFirst().allSatisfy {
                $0.contains("-- xx")
            },
            "drawer overtype must not issue a rewrite: \(overtypeRecord)"
        )
        XCTAssertEqual(caretUTF8 + 2, draft.utf8.count)
        XCTAssertNotNil(model.latestParse)

        let (expandedModel, expandedController, expandedText, expandedPanel, _) =
            try await openExpandedDrawerTitle("Release Notes")
        defer { expandedPanel.orderOut(nil) }
        let expandedDraft = "Prepare release\n- **Release Notes**"

        XCTAssertNil(expandedController.routeKeyDown(starEvent()))
        XCTAssertEqual(expandedText.string, expandedDraft)
        XCTAssertEqual(
            expandedText.selectedRange(),
            NSRange(location: (expandedDraft as NSString).length, length: 0)
        )
        XCTAssertNil(expandedModel.latestParse)
    }

    func testDrawerNewlineMenuPrecedenceAndReturnCapture() async throws {
        let draft = "Prepare release\n- **Release Notes**"
        let (model, controller, textView, panel, recordURL, fixtureURL, _) =
            try await openParsedDrawerTitle(draft, title: "Release Notes")
        defer { panel.orderOut(nil) }
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: draft.utf8.count,
            replacement: CaptureRange(start: draft.utf8.count, end: draft.utf8.count),
            context: "drawer",
            candidates: []
        )

        XCTAssertNil(controller.routeKeyDown(drawerTitleNewlineEvent("Shift-Return")))
        XCTAssertNotEqual(textView.string, "\(draft)\n  - ")
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(controller.routeKeyDown(keyEvent(keyCode: 36, characters: "\r")))
        await waitUntil { (try? String(contentsOf: recordURL))?.contains("argv=capture ") == true }
        XCTAssertTrue((try String(contentsOf: recordURL)).contains(draft))
    }

    func testDrawerTitleAssistRequiresFreshBobSpansAndAnUnmovedCaret() async throws {
        let draft = "Prepare release\n  - **Release Notes**"
        let (model, controller, textView, panel, _, fixtureURL, caretUTF8) =
            try await openParsedDrawerTitle(draft, title: "Release Notes")
        defer { panel.orderOut(nil) }
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let changedDraft = draft.replacingOccurrences(of: "Prepare", with: "Preparing")
        textView.string = changedDraft
        model.plainDraft = changedDraft
        let titleRange = changedDraft.range(of: "Release Notes")!
        let changedCaretUTF16 = NSMaxRange(NSRange(titleRange, in: changedDraft))
        let changedCaretUTF8 = changedDraft[..<titleRange.upperBound].utf8.count
        textView.setSelectedRange(NSRange(location: changedCaretUTF16, length: 0))
        model.editorTextDidChange(cursorUTF8Offset: changedCaretUTF8)
        XCTAssertNotNil(typeKey(starEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(
            textView.string,
            changedDraft.replacingOccurrences(of: "**Release Notes**", with: "**Release Notes***")
        )

        XCTAssertGreaterThan(caretUTF8, 0)
    }

    func testDrawerTitleAssistStaysNativeForSelectionOrdinaryAndUnannotatedBullets() async throws {
        for (draft, caretText) in [
            ("Prepare release\n  - Ordinary note", "Ordinary note"),
            ("Prepare release\n  - **Just bold**", "Just bold"),
        ] {
            let fixtureURL = try drawerParseFixtureURL(draft: draft, title: nil)
            let (model, controller, textView, panel, _) = try openDrawerDraft(
                draft,
                extra: ["FAKE_BOB_PARSE_FIXTURE": fixtureURL.path]
            )
            defer { panel.orderOut(nil) }
            defer { try? FileManager.default.removeItem(at: fixtureURL) }
            model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
            await waitUntil { model.latestParse?.input == draft }
            let range = draft.range(of: caretText)!
            let caretUTF16 = NSMaxRange(NSRange(range, in: draft))
            let caretUTF8 = draft[..<range.upperBound].utf8.count
            textView.setSelectedRange(NSRange(location: caretUTF16, length: 0))
            model.editorSelectionDidChange(cursorUTF8Offset: caretUTF8)
            let original = textView.string
            XCTAssertNotNil(
                typeKey(starEvent(), into: textView, model: model, controller: controller))
            XCTAssertNotEqual(textView.string, original, draft)
        }

        let selectedDraft = "Prepare release\n  - **Release Notes**"
        let (model, controller, textView, panel, _, fixtureURL, _) =
            try await openParsedDrawerTitle(selectedDraft, title: "Release Notes")
        defer { panel.orderOut(nil) }
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let titleRange = (selectedDraft as NSString).range(of: "Release Notes")
        let selected = NSRange(location: titleRange.location, length: 1)
        textView.setSelectedRange(selected)
        model.editorSelectionDidChange(cursorUTF8Offset: nil)
        XCTAssertNotNil(typeKey(starEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual((textView.string as NSString).substring(with: selected), "*")

        let midTitleDraft = "Prepare release\n  - **Release Notes**"
        let (midModel, midController, midText, midPanel, _, midFixture, _) =
            try await openParsedDrawerTitle(midTitleDraft, title: "Release Notes")
        defer { midPanel.orderOut(nil) }
        defer { try? FileManager.default.removeItem(at: midFixture) }
        let midRange = (midTitleDraft as NSString).range(of: "Release Notes")
        let middle = midRange.location + 4
        midText.setSelectedRange(NSRange(location: middle, length: 0))
        midModel.editorSelectionDidChange(
            cursorUTF8Offset: utf8Offset(in: midTitleDraft, utf16Offset: middle)
        )
        XCTAssertNotNil(
            typeKey(starEvent(), into: midText, model: midModel, controller: midController))
        XCTAssertNotEqual(midText.string, midTitleDraft)
    }

    func testMovingAwayFromExpandedDrawerTitleEndsTheOvertypeSession() async throws {
        let (model, controller, textView, panel, _) = try await openExpandedDrawerTitle(
            "Release Notes"
        )
        defer { panel.orderOut(nil) }

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        model.editorSelectionDidChange(cursorUTF8Offset: 0)
        let titleRange = (textView.string as NSString).range(of: "Release Notes")
        let titleEnd = NSMaxRange(titleRange)
        textView.setSelectedRange(NSRange(location: titleEnd, length: 0))
        model.editorSelectionDidChange(
            cursorUTF8Offset: utf8Offset(in: textView.string, utf16Offset: titleEnd)
        )

        XCTAssertNotNil(typeKey(starEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Prepare release\n- **Release Notes***")
    }

    func testEmptyDrawerSkeletonHasNoTitleNewlineAssist() async throws {
        let draft = "Prepare release\n- ****"
        let (model, controller, textView, panel, recordURL) = try openDrawerDraft(
            draft,
            extra: ["FAKE_BOB_PARSE_FIXTURE": "drawer-parse-empty-skeleton.json"]
        )
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: (draft as NSString).length - 2, length: 0))
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count - 2)
        await waitUntil { model.latestParse?.input == draft }

        XCTAssertNil(controller.routeKeyDown(drawerTitleNewlineEvent("Shift-Return")))
        XCTAssertFalse(textView.string.contains("\n  - "))
        let emptySkeletonRecord = (try? String(contentsOf: recordURL)) ?? ""
        XCTAssertTrue(
            emptySkeletonRecord.components(separatedBy: "argv=capture-rewrite").dropFirst()
                .allSatisfy { $0.contains("-- xx") },
            "empty skeleton must not issue a drawer rewrite: \(emptySkeletonRecord)"
        )
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
        let rewrites = record.components(separatedBy: "argv=capture-rewrite").dropFirst()
        XCTAssertTrue(
            rewrites.allSatisfy { $0.contains("-- xx") },
            "pasted star must not issue a drawer rewrite: \(record)"
        )
    }

    func testRequirementExpansionStillApplies() async throws {
        let (model, controller, textView, panel, _) = try openDrawerDraft(
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
