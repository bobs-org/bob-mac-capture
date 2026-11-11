import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Fast `..` / `;;` escapes and empty-picker restores for Bob's `.` → `&`
/// and `;` → `*` sigil aliases.
@MainActor
final class CaptureModifierAliasTests: XCTestCase {
    private var ledgerSuites: [String] = []

    override func tearDown() {
        MainActor.assumeIsolated {
            for suite in ledgerSuites {
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            }
            ledgerSuites.removeAll()
        }
        super.tearDown()
    }

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

    private func dotEvent(
        modifiers: NSEvent.ModifierFlags = [],
        timestamp: TimeInterval = 0,
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(keyCode: 47, characters: ".", modifiers: modifiers, timestamp: timestamp, isRepeat: isRepeat)
    }

    private func semicolonEvent(
        modifiers: NSEvent.ModifierFlags = [],
        timestamp: TimeInterval = 0,
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(keyCode: 41, characters: ";", modifiers: modifiers, timestamp: timestamp, isRepeat: isRepeat)
    }

    private func equalsEvent(
        modifiers: NSEvent.ModifierFlags = [],
        timestamp: TimeInterval = 0,
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(
            keyCode: 24,
            characters: "=",
            modifiers: modifiers,
            timestamp: timestamp,
            isRepeat: isRepeat
        )
    }

    private func spaceEvent() -> NSEvent {
        keyEvent(keyCode: 49, characters: " ")
    }

    private func escapeEvent() -> NSEvent {
        keyEvent(keyCode: 53, characters: "")
    }

    private func downEvent() -> NSEvent {
        keyEvent(keyCode: 125, characters: "")
    }

    private func makeHostedEditor(
        text: String
    ) -> (CapturePanelModel, CapturePanelController, NSTextView, NSPanel) {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        let suite = "org.bobs.bob-mac-capture.tests.modifier-tips.\(UUID().uuidString)"
        ledgerSuites.append(suite)
        model.aliasTipLedgerStore = AliasTipLedgerStore(defaults: UserDefaults(suiteName: suite)!)
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        model.plainDraft = text
        panel.contentView = textView
        XCTAssertTrue(panel.makeFirstResponder(textView))
        controller.replayedKeyForTesting = { event in
            textView.insertText(
                event.characters ?? "",
                replacementRange: textView.selectedRange()
            )
            model.plainDraft = textView.string
            let caretUTF8 = utf8Offset(
                in: textView.string,
                utf16Offset: textView.selectedRange().location
            ) ?? textView.string.utf8.count
            model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
        }
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
        timeout: TimeInterval = 10,
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

    private func weeklyHitCount(_ model: CapturePanelModel, id: String) -> Int {
        model.aliasTipLedgerStore.load().weeks.values
            .compactMap { $0[id]?.hits }
            .reduce(0, +)
    }

    private func openAlias(
        draft: String,
        key: String,
        rewrittenDraft: String,
        pickerSource: CapturePickerSource,
        typingTipsEnabled: Bool = true,
        timestamp: TimeInterval = 1
    ) async throws -> (CapturePanelModel, CapturePanelController, NSTextView, NSPanel) {
        let (model, controller, textView, panel) = makeHostedEditor(text: draft)
        model.typingTipsEnabled = typingTipsEnabled
        model.processClient = try processClient(recordURL: makeRecordURL())
        let event = key == "." ? dotEvent(timestamp: timestamp) : semicolonEvent(timestamp: timestamp)
        XCTAssertNotNil(typeKey(event, into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == rewrittenDraft
                && model.picker?.source == pickerSource
                && model.picker?.filterText.isEmpty == true
        }
        return (model, controller, textView, panel)
    }

    func testDotAndSemicolonAliasesOpenTheirBobSelectedPickers() async throws {
        let dot = try await openAlias(
            draft: "@home ", key: ".", rewrittenDraft: "@home &", pickerSource: .dependency
        )
        dot.3.orderOut(nil)
        XCTAssertEqual(dot.0.equalsGestureArm?.sigil, "&")
        XCTAssertEqual(dot.0.equalsGestureArm?.key, ".")

        let semicolon = try await openAlias(
            draft: "Buy milk ", key: ";", rewrittenDraft: "Buy milk *", pickerSource: .blockedTask
        )
        semicolon.3.orderOut(nil)
        XCTAssertEqual(semicolon.0.equalsGestureArm?.sigil, "*")
        XCTAssertEqual(semicolon.0.equalsGestureArm?.key, ";")
    }

    func testPickerAliasAdoptionsCountWithTipsOnAndOff() async throws {
        for tipsEnabled in [true, false] {
            let dependency = try await openAlias(
                draft: "@home ",
                key: ".",
                rewrittenDraft: "@home &",
                pickerSource: .dependency,
                typingTipsEnabled: tipsEnabled
            )
            XCTAssertEqual(weeklyHitCount(dependency.0, id: CaptureAliasLesson.dependency), 1)
            dependency.3.orderOut(nil)

            let blockedTask = try await openAlias(
                draft: "Buy milk ",
                key: ";",
                rewrittenDraft: "Buy milk *",
                pickerSource: .blockedTask,
                typingTipsEnabled: tipsEnabled
            )
            XCTAssertEqual(weeklyHitCount(blockedTask.0, id: CaptureAliasLesson.blockedTask), 1)
            blockedTask.3.orderOut(nil)
        }
    }

    func testDependencyPickerStillOpensWhenSelectionAnalysisWinsTheRace() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "@home ")
        defer { panel.orderOut(nil) }
        let delayMarker = makeRecordURL()
        defer { try? FileManager.default.removeItem(at: delayMarker) }
        model.processClient = try processClient(
            recordURL: makeRecordURL(),
            extra: [
                "FAKE_BOB_MODIFIER_ALIAS_COMPLETE_DELAY_SECONDS": "0.4",
                "FAKE_BOB_MODIFIER_ALIAS_COMPLETE_DELAY_MARKER": delayMarker.path,
            ]
        )
        XCTAssertNotNil(typeKey(dotEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "@home &"
                && model.equalsGestureArm?.isOpener == true
                && FileManager.default.fileExists(atPath: delayMarker.path)
        }
        XCTAssertNil(model.picker)

        model.editorSelectionDidChange(cursorUTF8Offset: 7)
        await waitUntil { model.picker?.source == .dependency }
        XCTAssertEqual(model.picker?.draftSnapshot, "@home &")
    }

    func testFastDoubleKeysEscapeEachAliasAndUndoRestoresBobSigil() async throws {
        let cases: [(draft: String, key: String, rewritten: String, literal: String, source: CapturePickerSource)] = [
            ("@home ", ".", "@home &", "@home .", .dependency),
            ("Buy milk ", ";", "Buy milk *", "Buy milk ;", .blockedTask),
        ]
        var panels: [NSPanel] = []
        defer { panels.forEach { $0.orderOut(nil) } }

        for item in cases {
            let (model, controller, textView, panel) = try await openAlias(
                draft: item.draft,
                key: item.key,
                rewrittenDraft: item.rewritten,
                pickerSource: item.source
            )
            panels.append(panel)
            let second = item.key == "." ? dotEvent(timestamp: 1.2) : semicolonEvent(timestamp: 1.2)
            let lesson = item.key == "."
                ? CaptureAliasLesson.dependency
                : CaptureAliasLesson.blockedTask
            XCTAssertEqual(weeklyHitCount(model, id: lesson), 1)
            XCTAssertNil(controller.routeKeyDown(second))
            XCTAssertEqual(textView.string, item.literal)
            XCTAssertEqual(weeklyHitCount(model, id: lesson), 0)
            XCTAssertNil(model.picker)
            XCTAssertFalse(model.pickerVisible)
            XCTAssertNil(model.equalsGestureArm)

            textView.undoManager?.undo()
            XCTAssertEqual(textView.string, item.rewritten)
        }
    }

    func testSlowSecondAliasKeyFallsThroughToPickerFilter() async throws {
        let (model, controller, _, panel) = try await openAlias(
            draft: "Buy milk ", key: ";", rewrittenDraft: "Buy milk *", pickerSource: .blockedTask
        )
        defer { panel.orderOut(nil) }

        let event = semicolonEvent(timestamp: 1.351)
        XCTAssertNotNil(controller.routeKeyDown(event))
        model.updatePickerFilter(";")
        XCTAssertEqual(model.picker?.filterText, ";")
        XCTAssertEqual(model.plainDraft, "Buy milk *")
        XCTAssertNil(model.equalsGestureArm)
    }

    func testSpaceAndEscapeRestoreOnlyAnEmptyAliasPicker() async throws {
        let space = try await openAlias(
            draft: "@home ", key: ".", rewrittenDraft: "@home &", pickerSource: .dependency
        )
        XCTAssertNil(space.1.routeKeyDown(spaceEvent()))
        XCTAssertEqual(space.2.string, "@home . ")
        XCTAssertNil(space.0.picker)
        XCTAssertEqual(weeklyHitCount(space.0, id: CaptureAliasLesson.dependency), 0)
        space.3.orderOut(nil)

        let escape = try await openAlias(
            draft: "Buy milk ", key: ";", rewrittenDraft: "Buy milk *", pickerSource: .blockedTask
        )
        XCTAssertNil(escape.1.routeKeyDown(escapeEvent()))
        XCTAssertEqual(escape.2.string, "Buy milk ;")
        XCTAssertNil(escape.0.picker)
        XCTAssertEqual(weeklyHitCount(escape.0, id: CaptureAliasLesson.blockedTask), 0)
        escape.3.orderOut(nil)

        let filtered = try await openAlias(
            draft: "Buy milk ", key: ";", rewrittenDraft: "Buy milk *", pickerSource: .blockedTask
        )
        filtered.0.updatePickerFilter("shoes")
        XCTAssertFalse(filtered.0.relationEqualsOpenerRestorable)
        XCTAssertFalse(filtered.0.restoreRelationEqualsOpener(key: " "))
        XCTAssertNotNil(filtered.1.routeKeyDown(spaceEvent()))
        XCTAssertEqual(filtered.2.string, "Buy milk *")
        XCTAssertEqual(weeklyHitCount(filtered.0, id: CaptureAliasLesson.blockedTask), 1)
        XCTAssertNil(filtered.0.equalsGestureArm)
        filtered.3.orderOut(nil)
    }

    func testSpaceAndEscapeRestoreBeforeDelayedPickerForAllModifierAliases() async throws {
        let cases:
            [(
                draft: String,
                key: String,
                rewritten: String,
                trigger: NSEvent,
                delayKey: String
            )] = [
                (
                    "@home ",
                    ".",
                    "@home &",
                    dotEvent(),
                    "FAKE_BOB_MODIFIER_ALIAS_COMPLETE_DELAY_SECONDS"
                ),
                (
                    "Buy milk ",
                    ";",
                    "Buy milk *",
                    semicolonEvent(),
                    "FAKE_BOB_MODIFIER_ALIAS_COMPLETE_DELAY_SECONDS"
                ),
                (
                    "Fix it ",
                    "=",
                    "Fix it ~",
                    equalsEvent(),
                    "FAKE_BOB_RELATION_EQUALS_COMPLETE_DELAY_SECONDS"
                ),
            ]

        for restoreWithSpace in [true, false] {
            for item in cases {
                let (model, controller, textView, panel) = makeHostedEditor(text: item.draft)
                let delayMarker = makeRecordURL()
                var extra = [item.delayKey: "0.4"]
                let markerKey =
                    item.delayKey == "FAKE_BOB_MODIFIER_ALIAS_COMPLETE_DELAY_SECONDS"
                    ? "FAKE_BOB_MODIFIER_ALIAS_COMPLETE_DELAY_MARKER"
                    : "FAKE_BOB_RELATION_EQUALS_COMPLETE_DELAY_MARKER"
                extra[markerKey] = delayMarker.path
                model.processClient = try processClient(recordURL: makeRecordURL(), extra: extra)

                XCTAssertNotNil(
                    typeKey(item.trigger, into: textView, model: model, controller: controller)
                )
                await waitUntil {
                    textView.string == item.rewritten
                        && model.equalsGestureArm?.isOpener == true
                        && FileManager.default.fileExists(atPath: delayMarker.path)
                }
                XCTAssertNil(model.picker)
                XCTAssertTrue(model.relationEqualsOpenerRestorable)

                let restoreEvent = restoreWithSpace ? spaceEvent() : escapeEvent()
                XCTAssertNil(controller.routeKeyDown(restoreEvent))
                let restored = item.draft + item.key + (restoreWithSpace ? " " : "")
                XCTAssertEqual(textView.string, restored)
                let lesson: String
                switch item.key {
                case ".":
                    lesson = CaptureAliasLesson.dependency
                case ";":
                    lesson = CaptureAliasLesson.blockedTask
                default:
                    lesson = CaptureAliasLesson.relation
                }
                XCTAssertEqual(weeklyHitCount(model, id: lesson), 0)
                XCTAssertNil(model.picker)
                XCTAssertNil(model.equalsGestureArm)

                // Let the delayed completion attempt to return after restoration.
                try await Task.sleep(nanoseconds: 600_000_000)
                XCTAssertEqual(textView.string, restored)
                XCTAssertEqual(model.plainDraft, restored)
                XCTAssertNil(model.picker)
                XCTAssertFalse(model.completionVisible)
                panel.orderOut(nil)
                try? FileManager.default.removeItem(at: delayMarker)
            }
        }
    }

    func testPreReplyDoubleKeysCollapseOnBobAliasAndUnchangedReplyLeavesBoth() async throws {
        let cases: [(draft: String, key: String, alias: String, literal: String, unchanged: Bool)] = [
            ("@home ", ".", "@home &", "@home .", false),
            ("Buy milk ", ";", "Buy milk *", "Buy milk ;", false),
            ("Buy milk ", ";", "Buy milk *", "Buy milk ;;", true),
        ]
        var panels: [NSPanel] = []
        defer { panels.forEach { $0.orderOut(nil) } }

        for item in cases {
            let (model, controller, textView, panel) = makeHostedEditor(text: item.draft)
            panels.append(panel)
            var extra = ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
            if item.unchanged {
                extra["FAKE_BOB_MODIFIER_ALIAS_UNCHANGED"] = "1"
            }
            model.processClient = try processClient(recordURL: makeRecordURL(), extra: extra)
            let first = item.key == "." ? dotEvent(timestamp: 1.0) : semicolonEvent(timestamp: 1.0)
            let second = item.key == "." ? dotEvent(timestamp: 1.1) : semicolonEvent(timestamp: 1.1)
            XCTAssertNotNil(typeKey(first, into: textView, model: model, controller: controller))
            XCTAssertNotNil(typeKey(second, into: textView, model: model, controller: controller))
            await waitUntil { textView.string == item.literal && model.equalsProbe == nil }
            XCTAssertNil(model.equalsGestureArm)
            XCTAssertNil(model.picker)
        }
    }

    func testInterveningNavigationModifierAndCaretMoveDisarmTheSemicolonAlias() async throws {
        let navigation = try await openAlias(
            draft: "Buy milk ", key: ";", rewrittenDraft: "Buy milk *", pickerSource: .blockedTask
        )
        _ = navigation.1.routeKeyDown(downEvent())
        XCTAssertNil(navigation.0.equalsGestureArm)
        XCTAssertEqual(navigation.0.plainDraft, "Buy milk *")
        navigation.3.orderOut(nil)

        let modified = try await openAlias(
            draft: "Buy milk ", key: ";", rewrittenDraft: "Buy milk *", pickerSource: .blockedTask
        )
        _ = modified.1.routeKeyDown(semicolonEvent(modifiers: .command, timestamp: 1.2))
        XCTAssertNil(modified.0.equalsGestureArm)
        XCTAssertEqual(modified.0.plainDraft, "Buy milk *")
        modified.3.orderOut(nil)

        let caret = try await openAlias(
            draft: "Buy milk ", key: ";", rewrittenDraft: "Buy milk *", pickerSource: .blockedTask
        )
        caret.2.setSelectedRange(NSRange(location: 0, length: 0))
        caret.0.editorSelectionDidChange(cursorUTF8Offset: 0)
        XCTAssertNil(caret.0.equalsGestureArm)
        caret.3.orderOut(nil)
    }

    func testInterveningKeyBeforeReplyCannotRearmSemicolonEscape() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "Buy milk ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: makeRecordURL(),
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
        )
        XCTAssertNotNil(typeKey(semicolonEvent(timestamp: 1.0), into: textView, model: model, controller: controller))
        _ = controller.routeKeyDown(downEvent())
        XCTAssertNil(model.pendingEqualsFirstKey)
        await waitUntil { textView.string == "Buy milk *" && model.picker?.source == .blockedTask }
        XCTAssertNil(model.equalsGestureArm)
        XCTAssertFalse(model.restoreRelationEqualsOpener(key: ""))
        XCTAssertEqual(textView.string, "Buy milk *")
    }

    func testDotRouteAndExistingMarkerAliasesKeepTheirPriorReplies() async throws {
        let route = makeHostedEditor(text: "Buy milk ")
        route.0.processClient = try processClient(recordURL: makeRecordURL())
        XCTAssertNotNil(typeKey(dotEvent(), into: route.2, model: route.0, controller: route.1))
        await waitUntil { route.2.string == "Buy milk @" && route.0.completionVisible }
        XCTAssertEqual(route.0.equalsGestureArm?.sigil, "@")
        route.3.orderOut(nil)

        let recordURL = makeRecordURL()
        let dotCaret = makeHostedEditor(text: "@file")
        dotCaret.0.processClient = try processClient(recordURL: recordURL)
        XCTAssertNotNil(typeKey(dotEvent(), into: dotCaret.2, model: dotCaret.0, controller: dotCaret.1))
        await waitUntil { dotCaret.2.string == "@file^" }
        XCTAssertNil(dotCaret.0.equalsGestureArm)
        dotCaret.3.orderOut(nil)

        let semicolonColon = makeHostedEditor(text: "@file")
        semicolonColon.0.processClient = try processClient(recordURL: makeRecordURL())
        XCTAssertNotNil(typeKey(
            semicolonEvent(), into: semicolonColon.2, model: semicolonColon.0, controller: semicolonColon.1
        ))
        await waitUntil { semicolonColon.2.string == "@file:" }
        XCTAssertNil(semicolonColon.0.equalsGestureArm)
        semicolonColon.3.orderOut(nil)
    }

    func testTypedSemicolonProbeRequiresPendingSemicolon() {
        let event = semicolonEvent(timestamp: 1.1)
        XCTAssertNil(CaptureKeyCommandRouter.typedEqualsProbeKey(event: event, modifiers: []))
        XCTAssertEqual(
            CaptureKeyCommandRouter.typedEqualsProbeKey(
                event: event,
                modifiers: [],
                pendingFirstKey: ";"
            ),
            ";"
        )
    }
}
