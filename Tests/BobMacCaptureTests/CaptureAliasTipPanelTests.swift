import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureAliasTipPanelTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var hostedWindows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        suiteName = "org.bobs.bob-mac-capture.tests.tips.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        hostedWindows.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testTipIsInTheListsFirstFrame() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            debounceNanoseconds: 200_000_000
        )
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil {
            model.completionVisible && model.presentedAliasTip != nil
        }
        XCTAssertEqual(model.presentedAliasTip?.id, CaptureAliasLesson.routeAfterText)
        XCTAssertEqual(model.aliasTipSessionForTesting.didShowTip, true)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .tipsShown,
            1
        )
        XCTAssertTrue(
            (try String(contentsOf: recordURL)).contains(
                "argv=capture-rewrite --cursor 10 --format json -- Buy milk @"
            )
        )
    }

    func testLateTipReplyIsDroppedOnceTheListIsOpen() async throws {
        let recordURL = makeRecordURL()
        let release = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_RELEASE_PATH": release.path],
            debounceNanoseconds: 0
        )
        model.aliasTipTimeout = 4
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        XCTAssertTrue(model.aliasTipInFlightForTesting)
        defer { FileManager.default.createFile(atPath: release.path, contents: Data()) }
        await waitUntil { model.completionVisible }
        XCTAssertNil(model.presentedAliasTip)
        FileManager.default.createFile(atPath: release.path, contents: Data())
        await waitUntil { !model.aliasTipInFlightForTesting }
        XCTAssertNil(model.presentedAliasTip)
        XCTAssertNil(model.pendingAliasTipForTesting)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .tipsShown,
            0
        )
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .recent,
            [.miss]
        )
    }

    func testEditBeforeTheReplyDropsTheTip() async throws {
        let recordURL = makeRecordURL()
        let release = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_RELEASE_PATH": release.path],
            debounceNanoseconds: 0
        )
        model.aliasTipTimeout = 4
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        defer { FileManager.default.createFile(atPath: release.path, contents: Data()) }
        restorePrefix("Buy milk ", into: textView, model: model)
        model.editorTextDidChange(
            cursorUTF8Offset: "Buy milk ".utf8.count
        )
        FileManager.default.createFile(atPath: release.path, contents: Data())
        await waitUntil { !model.aliasTipInFlightForTesting }
        XCTAssertNil(model.presentedAliasTip)
        XCTAssertNil(model.pendingAliasTipForTesting)
    }

    func testUnshiftedRepeatPasteAndTipsOffSpawnNothing() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeModel(recordURL: recordURL)

        CapturePanelController.noteTypedSigilIntentIfEligible(
            event: keyEvent(characters: "@", modifiers: []),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        insert("@", into: textView, model: model)
        XCTAssertFalse(model.aliasTipInFlightForTesting)

        restorePrefix("Buy milk ", into: textView, model: model)
        CapturePanelController.noteTypedSigilIntentIfEligible(
            event: keyEvent(characters: "@", modifiers: .shift, isRepeat: true),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        insert("@", into: textView, model: model)
        XCTAssertFalse(model.aliasTipInFlightForTesting)

        restorePrefix("Buy milk ", into: textView, model: model)
        insert("@", into: textView, model: model)
        XCTAssertFalse(model.aliasTipInFlightForTesting)

        model.typingTipsEnabled = false
        restorePrefix("Buy milk ", into: textView, model: model)
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        XCTAssertFalse(model.aliasTipInFlightForTesting)
        XCTAssertEqual(captureRewriteCount(in: recordURL, draft: "Buy milk @"), 0)
    }

    func testSecondEligibleSigilInASessionShowsNoTip() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            debounceNanoseconds: 200_000_000
        )
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil {
            model.completionVisible && model.presentedAliasTip != nil
        }
        model.dismissCompletion()
        restorePrefix("Buy milk ", into: textView, model: model)
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil { !model.aliasTipInFlightForTesting }
        XCTAssertNil(model.presentedAliasTip)
        XCTAssertEqual(model.aliasTipSessionForTesting.didShowTip, true)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .tipsShown,
            1
        )
    }

    func testOldBobDisablesTheTipLane() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            extra: ["FAKE_BOB_ALIAS_TIP": "old"]
        )
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil { !model.aliasTipInFlightForTesting }
        XCTAssertNil(model.presentedAliasTip)
        let first = captureRewriteCount(in: recordURL, draft: "Buy milk @")
        XCTAssertEqual(first, 1)
        restorePrefix("Buy milk ", into: textView, model: model)
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        XCTAssertFalse(model.aliasTipInFlightForTesting)
        XCTAssertEqual(captureRewriteCount(in: recordURL, draft: "Buy milk @"), 1)
    }

    func testHitIsRecordedAndUndoWithdrawsIt() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeHostedModel(recordURL: recordURL)
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: ".", modifiers: []),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        insert(".", into: textView, model: model)
        await waitUntil { textView.string == "Buy milk @" }
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().weeks.values.first?[
                CaptureAliasLesson.routeAfterText
            ]?.hits,
            1
        )
        textView.undoManager?.undo()
        model.plainDraft = textView.string
        let caretUTF16 = textView.selectedRange().location
        let caret = utf8Offset(
            in: textView.string,
            utf16Offset: caretUTF16
        ) ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caret)
        XCTAssertEqual(textView.string, "Buy milk .")
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .recent,
            []
        )
        XCTAssertTrue(
            model.aliasTipSessionForTesting.escapedLessons.contains(
                CaptureAliasLesson.routeAfterText
            )
        )
    }

    func testSpaceRestoreWithdrawsTheHit() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeHostedModel(recordURL: recordURL)
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: ".", modifiers: []),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        insert(".", into: textView, model: model)
        await waitUntil { textView.string == "Buy milk @" && model.equalsGestureArm != nil }
        XCTAssertTrue(model.restoreRelationEqualsOpener(key: " "))
        XCTAssertEqual(textView.string, "Buy milk . ")
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .recent,
            []
        )
    }

    func testHashLiteralEscapeWithdrawsTheHit() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeHostedModel(
            recordURL: recordURL,
            text: "jot idea "
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "/", modifiers: []),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        insert("/", into: textView, model: model)
        await waitUntil { textView.string == "jot idea #" }
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().weeks.values.first?[
                CaptureAliasLesson.hashMenu
            ]?.hits,
            1
        )
        let arm = try XCTUnwrap(model.hashAliasLiteralArm)
        XCTAssertTrue(model.replaceHashAliasWithLiteralKey(arm))
        XCTAssertEqual(textView.string, "jot idea /")
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.hashMenu]?.recent,
            []
        )
    }

    func testDraftMatchesWithTipsOnAndOff() async throws {
        let onRecord = makeRecordURL()
        let (onModel, onView) = try makeModel(recordURL: onRecord)
        typeSigil("@", into: onView, model: onModel, modifiers: .shift)
        await waitUntil { !onModel.aliasTipInFlightForTesting }
        let offRecord = makeRecordURL()
        let (offModel, offView) = try makeModel(recordURL: offRecord)
        offModel.typingTipsEnabled = false
        typeSigil("@", into: offView, model: offModel, modifiers: .shift)
        XCTAssertEqual(onModel.plainDraft, offModel.plainDraft)
        XCTAssertEqual(onView.string, offView.string)
        XCTAssertEqual(onModel.plainDraft, "Buy milk @")
    }

    func testOptionTypedHashOpensTheHashTip() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            debounceNanoseconds: 200_000_000,
            text: "jot idea "
        )
        typeSigil("#", into: textView, model: model, modifiers: .option)
        await waitUntil {
            model.completionVisible && model.presentedAliasTip != nil
        }
        XCTAssertEqual(model.presentedAliasTip?.id, CaptureAliasLesson.hashMenu)
    }

    private func makeModel(
        recordURL: URL,
        extra: [String: String] = [:],
        debounceNanoseconds: UInt64 = 50_000_000,
        text: String = "Buy milk "
    ) throws -> (CapturePanelModel, NSTextView) {
        let model = CapturePanelModel(debounceNanoseconds: debounceNanoseconds)
        model.aliasTipLedgerStore = AliasTipLedgerStore(defaults: defaults)
        model.typingTipsEnabled = true
        model.processClient = try processClient(recordURL: recordURL, extra: extra)
        let textView = makeTextView(text)
        model.plainDraft = text
        return (model, textView)
    }

    private func makeHostedModel(
        recordURL: URL,
        extra: [String: String] = [:],
        text: String = "Buy milk "
    ) throws -> (CapturePanelModel, NSTextView) {
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            extra: extra,
            debounceNanoseconds: 0,
            text: text
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        hostedWindows.append(window)
        model.applyNativeRewriteEdit = { edit in
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: textView
            )
        }
        return (model, textView)
    }

    private func restorePrefix(
        _ text: String,
        into textView: NSTextView,
        model: CapturePanelModel
    ) {
        model.plainDraft = text
        textView.string = text
        textView.setSelectedRange(
            NSRange(location: (text as NSString).length, length: 0)
        )
    }

    private func typeSigil(
        _ sigil: String,
        into textView: NSTextView,
        model: CapturePanelModel,
        modifiers: NSEvent.ModifierFlags
    ) {
        CapturePanelController.noteTypedSigilIntentIfEligible(
            event: keyEvent(characters: sigil, modifiers: modifiers),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        insert(sigil, into: textView, model: model)
    }

    private func insert(
        _ typed: String,
        into textView: NSTextView,
        model: CapturePanelModel
    ) {
        textView.insertText(typed, replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        let caretUTF8 =
            utf8Offset(
                in: textView.string,
                utf16Offset: textView.selectedRange().location
            ) ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
    }

    private func makeTextView(_ text: String) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    private func keyEvent(
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
            keyCode: 19
        )!
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

    private func makeRecordURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func captureRewriteCount(in recordURL: URL, draft: String) -> Int {
        let record = (try? String(contentsOf: recordURL)) ?? ""
        let needle = "argv=capture-rewrite --cursor 10 --format json -- \(draft)"
        return record.components(separatedBy: needle).count - 1
    }

    private func waitUntil(
        timeout: TimeInterval = 8,
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
}
