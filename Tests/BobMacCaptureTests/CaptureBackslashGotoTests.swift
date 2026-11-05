import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Backslash opens Go To (`\` types `/` from a blank draft; a second `\`
/// types a literal). Router, insertion helper, model, and live fake-bob
/// wiring for the `literal_backslash = double` branch.
@MainActor
final class CaptureBackslashGotoTests: XCTestCase {
    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = "",
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

    private func backslashEvent(
        keyCode: UInt16 = 42,
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(
            keyCode: keyCode,
            modifiers: modifiers,
            characters: "\\",
            isRepeat: isRepeat
        )
    }

    // MARK: - Router, editor branch

    func testBlankDraftBackslashOpensGoto() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(draftIsBlank: true)
            ),
            .openGotoFromBackslash
        )
    }

    func testBackslashMatchesByCharactersNotKeyCode() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(draftIsBlank: true)
        XCTAssertEqual(
            router.command(for: backslashEvent(keyCode: 50), context: context),
            .openGotoFromBackslash
        )
        XCTAssertEqual(
            router.command(
                for: backslashEvent(modifiers: .option),
                context: context
            ),
            .openGotoFromBackslash
        )
        XCTAssertEqual(
            router.command(
                for: backslashEvent(modifiers: .shift),
                context: context
            ),
            .openGotoFromBackslash
        )
    }

    func testCommandBackslashStillOpensTodayPomodoro() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(modifiers: .command),
                context: CaptureKeyRoutingContext(draftIsBlank: true)
            ),
            .openTodayPomodoro
        )
    }

    func testControlBackslashIsUnbound() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(
                for: backslashEvent(modifiers: .control),
                context: CaptureKeyRoutingContext(draftIsBlank: true)
            )
        )
    }

    func testMarkedTextLeavesBackslashToTextSystem() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    draftIsBlank: true,
                    editorHasMarkedText: true
                )
            )
        )
    }

    func testNonBlankDraftTypesBackslashNatively() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(for: backslashEvent(), context: CaptureKeyRoutingContext())
        )
    }

    func testRepeatOnBlankDraftIsConsumed() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    keyIsRepeat: true,
                    draftIsBlank: true
                )
            ),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(
                for: backslashEvent(isRepeat: true),
                context: CaptureKeyRoutingContext(draftIsBlank: true)
            ),
            .consumeKey
        )
    }

    func testBareGotoArmedTypesLiteralInEditor() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    draftIsBareGotoSigil: true,
                    backslashLiteralArmed: true
                )
            ),
            .typeLiteralBackslash
        )
    }

    func testBareGotoChipReopensPicker() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    pickerChipVisible: true,
                    draftIsBareGotoSigil: true
                )
            ),
            .openPickerFromChip
        )
    }

    func testBareGotoWithoutArmOrChipIsConsumed() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(draftIsBareGotoSigil: true)
            ),
            .consumeKey
        )
    }

    func testBareGotoRepeatIsConsumed() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    keyIsRepeat: true,
                    draftIsBareGotoSigil: true,
                    backslashLiteralArmed: true
                )
            ),
            .consumeKey
        )
    }

    // MARK: - Router, picker branch

    func testPickerBareGotoArmedTypesLiteral() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskGoto: true,
                    pickerFilterIsEmpty: true,
                    draftIsBareGotoSigil: true,
                    backslashLiteralArmed: true
                )
            ),
            .typeLiteralBackslash
        )
    }

    func testPickerBareGotoUnarmedIsConsumed() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskGoto: true,
                    pickerFilterIsEmpty: true,
                    draftIsBareGotoSigil: true
                )
            ),
            .consumeKey
        )
    }

    func testPickerGotoWithFilterLeavesBackslashNative() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskGoto: true,
                    pickerFilterIsEmpty: false,
                    draftIsBareGotoSigil: true
                )
            )
        )
    }

    func testTaskLinkPickerLeavesBackslashNative() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskLink: true,
                    pickerFilterIsEmpty: true,
                    draftIsBareGotoSigil: true
                )
            )
        )
    }

    func testPickerDispatchInFlightKeepsPrecedence() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskGoto: true,
                    pickerDispatchInFlight: true,
                    pickerFilterIsEmpty: true,
                    draftIsBareGotoSigil: true,
                    backslashLiteralArmed: true
                )
            ),
            .consumeKey
        )
    }

    func testModalSurfacesOwnBackslash() {
        let router = CaptureKeyCommandRouter()
        let event = backslashEvent()
        let blank = CaptureKeyRoutingContext(
            draftIsBlank: true,
            draftIsBareGotoSigil: false
        )
        XCTAssertNotEqual(
            router.command(
                for: event,
                context: {
                    var context = blank
                    context.stashPickerVisible = true
                    context.stashEntryCount = 3
                    return context
                }()
            ),
            .openGotoFromBackslash
        )
        XCTAssertNotEqual(
            router.command(
                for: event,
                context: {
                    var context = blank
                    context.templateShelfVisible = true
                    context.templateEntryCount = 3
                    return context
                }()
            ),
            .openGotoFromBackslash
        )
        XCTAssertNotEqual(
            router.command(
                for: event,
                context: {
                    var context = blank
                    context.taskIDPromptVisible = true
                    return context
                }()
            ),
            .openGotoFromBackslash
        )
    }

    // MARK: - Insertion helper

    func testInsertHelperReplacesBlankDraftAndArms() {
        let model = CapturePanelModel()
        let textView = NSTextView()
        textView.isEditable = true
        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(
            CapturePanelController.insertGotoSigilForBackslashInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "/")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertTrue(model.backslashLiteralArmed)
    }

    func testInsertHelperReplacesWhitespaceDraft() {
        let model = CapturePanelModel()
        model.plainDraft = "  \n"
        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "  \n"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertTrue(
            CapturePanelController.insertGotoSigilForBackslashInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "/")
    }

    func testInsertHelperDeclinesWithoutChangingText() {
        let model = CapturePanelModel()
        model.plainDraft = "x1"
        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "x1"
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertFalse(
            CapturePanelController.insertGotoSigilForBackslashInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "x1")
        XCTAssertFalse(model.backslashLiteralArmed)
    }

    func testInsertHelperDeclinesWhileComposingSubmittingOrLocked() {
        let model = CapturePanelModel()
        let textView = NSTextView()
        textView.isEditable = true
        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.setMarkedText(
            "\\",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 0, length: 0)
        )
        XCTAssertFalse(
            CapturePanelController.insertGotoSigilForBackslashInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        textView.unmarkText()

        model.isSubmitting = true
        XCTAssertFalse(
            CapturePanelController.insertGotoSigilForBackslashInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        model.isSubmitting = false

        model.setEditorInputLockedForTests(true)
        XCTAssertFalse(
            CapturePanelController.insertGotoSigilForBackslashInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        model.setEditorInputLockedForTests(false)
        XCTAssertEqual(textView.string, "")
    }

    // MARK: - Model

    func testDraftIsBareGotoSigilTrimsWhitespace() {
        let model = CapturePanelModel()
        model.plainDraft = "  /  "
        XCTAssertTrue(model.draftIsBareGotoSigil)
        model.plainDraft = "/dee"
        XCTAssertFalse(model.draftIsBareGotoSigil)
        model.plainDraft = ""
        XCTAssertFalse(model.draftIsBareGotoSigil)
    }

    func testPrepareForDismissalClearsBackslashArm() {
        let model = CapturePanelModel()
        model.armBackslashLiteral()
        XCTAssertTrue(model.backslashLiteralArmed)
        model.prepareForDismissal()
        XCTAssertFalse(model.backslashLiteralArmed)
    }

    func testTakeBackslashArmClears() {
        let model = CapturePanelModel()
        model.armBackslashLiteral()
        XCTAssertTrue(model.takeBackslashLiteralArm())
        XCTAssertFalse(model.backslashLiteralArmed)
        XCTAssertFalse(model.takeBackslashLiteralArm())
    }

    func testReplaceGotoSigilWithLiteralBackslash() {
        let model = CapturePanelModel()
        model.installTaskGotoPickerForPreviews(
            candidates: [],
            draft: "/",
            replacement: CaptureRange(start: 0, end: 1)
        )
        model.replaceGotoSigilWithLiteralBackslash()
        XCTAssertEqual(model.plainDraft, "\\")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.pickerChip)
    }

    func testReplaceGotoSigilDeclinesWhenNotBare() {
        let model = CapturePanelModel()
        model.plainDraft = "/dee"
        model.replaceGotoSigilWithLiteralBackslash()
        XCTAssertEqual(model.plainDraft, "/dee")
    }

    // MARK: - Live, with the fake bob

    private func gotoModel(
        stash: CanceledDraftStash? = nil,
        extraEnvironment: [String: String] = [:]
    ) throws -> (CapturePanelModel, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": url.path,
        ]
        environment.merge(extraEnvironment) { _, replacement in replacement }
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: environment
            ),
            debounceNanoseconds: 5_000_000,
            canceledDraftStash: stash
        )
        return (model, url)
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

    func testLiveBackslashAliasOpensGotoWithOneCaptureComplete() async throws {
        let (model, recordURL) = try gotoModel()
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }

        XCTAssertTrue(model.pickerSourceIsTaskGoto)
        XCTAssertEqual(model.picker?.filterText, "")
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-complete").count - 1, 1)
    }

    func testLiveSecondBackslashTypesLiteralAndClosesPicker() async throws {
        let (model, _) = try gotoModel()
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }

        model.replaceGotoSigilWithLiteralBackslash()
        XCTAssertEqual(model.plainDraft, "\\")
        XCTAssertTrue(model.hasDraft)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.pickerChip)
        XCTAssertFalse(model.draftIsBareGotoSigil)
    }

    func testLiveArmClearedByTakeAndDismissal() {
        let router = CaptureKeyCommandRouter()
        let bare = CaptureKeyRoutingContext(
            draftIsBareGotoSigil: true,
            backslashLiteralArmed: true
        )
        XCTAssertEqual(
            router.command(for: backslashEvent(), context: bare),
            .typeLiteralBackslash
        )
        let model = CapturePanelModel()
        model.armBackslashLiteral()
        XCTAssertTrue(model.takeBackslashLiteralArm())
        XCTAssertFalse(model.backslashLiteralArmed)
        let consumed = CaptureKeyRoutingContext(
            draftIsBareGotoSigil: true,
            backslashLiteralArmed: false
        )
        XCTAssertEqual(
            router.command(for: backslashEvent(), context: consumed),
            .consumeKey
        )
        model.armBackslashLiteral()
        model.prepareForDismissal()
        XCTAssertFalse(model.backslashLiteralArmed)
    }

    func testLiveCtrlCAfterAliasDiscardsInsteadOfStashing() async throws {
        let stash = CanceledDraftStash(capacity: 10)
        let (model, _) = try gotoModel(stash: stash)
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }
        model.stashDraftAndClose()
        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(model.plainDraft, "")
    }

    // MARK: - Hash alias double-tap

    func testHashAliasArmedTypesLiteral() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(hashAliasLiteralArmed: true)
            ),
            .typeLiteralBackslashForHashAlias
        )
    }

    func testHashAliasArmedRepeatIsConsumed() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(isRepeat: true),
                context: CaptureKeyRoutingContext(hashAliasLiteralArmed: true)
            ),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    keyIsRepeat: true,
                    hashAliasLiteralArmed: true
                )
            ),
            .consumeKey
        )
    }

    func testHashAliasArmedWithMarkedTextIsNil() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    hashAliasLiteralArmed: true,
                    editorHasMarkedText: true
                )
            )
        )
    }

    func testHashAliasArmedCommandBackslashOpensToday() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(modifiers: .command),
                context: CaptureKeyRoutingContext(hashAliasLiteralArmed: true)
            ),
            .openTodayPomodoro
        )
    }

    func testPendingBackslashBeforeReplyReasks() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(hashAliasReplyPending: true)
            ),
            .typeBackslashBeforeHashAliasReply
        )
    }

    func testPendingRepeatStaysNative() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(
                for: backslashEvent(isRepeat: true),
                context: CaptureKeyRoutingContext(hashAliasReplyPending: true)
            )
        )
        XCTAssertNil(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    keyIsRepeat: true,
                    hashAliasReplyPending: true
                )
            )
        )
    }

    func testArmedBeatsPending() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    hashAliasLiteralArmed: true,
                    hashAliasReplyPending: true
                )
            ),
            .typeLiteralBackslashForHashAlias
        )
    }

    func testPendingWithMarkedTextIsNil() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    hashAliasReplyPending: true,
                    editorHasMarkedText: true
                )
            )
        )
    }

    func testPendingCommandBackslashOpensToday() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(modifiers: .command),
                context: CaptureKeyRoutingContext(hashAliasReplyPending: true)
            ),
            .openTodayPomodoro
        )
    }

    func testPendingBlankDraftStillOpensGoto() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    draftIsBlank: true,
                    hashAliasReplyPending: true
                )
            ),
            .openGotoFromBackslash
        )
    }

    func testPendingBareGotoRouteIsUnchanged() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: backslashEvent(),
                context: CaptureKeyRoutingContext(
                    draftIsBareGotoSigil: true,
                    hashAliasReplyPending: true
                )
            ),
            .consumeKey
        )
    }

    func testUnarmedNonBlankBackslashIsNil() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(for: backslashEvent(), context: CaptureKeyRoutingContext())
        )
    }

    func testHashArmSetOnlyForHashAliasEdit() {
        let model = CapturePanelModel()
        XCTAssertNil(model.hashAliasLiteralArm)
        model.hashAliasLiteralArm = CaptureHashAliasArm(
            draft: "jot idea #",
            hashUTF8: 9,
            caretUTF8: 10,
            caretUTF16: 10,
            hashUTF16Range: NSRange(location: 9, length: 1)
        )
        XCTAssertNotNil(model.takeHashAliasLiteralArm())
        XCTAssertNil(model.hashAliasLiteralArm)
        model.hashAliasLiteralArm = CaptureHashAliasArm(
            draft: "jot idea #",
            hashUTF8: 9,
            caretUTF8: 10,
            caretUTF16: 10,
            hashUTF16Range: NSRange(location: 9, length: 1)
        )
        model.prepareForDismissal()
        XCTAssertNil(model.hashAliasLiteralArm)
    }

    func testStaleHashArmIsInert() {
        let model = CapturePanelModel()
        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "jot idea #b"
        textView.setSelectedRange(NSRange(location: 11, length: 0))
        model.applyNativeRewriteEdit = { edit in
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: textView
            )
        }
        let arm = CaptureHashAliasArm(
            draft: "jot idea #",
            hashUTF8: 9,
            caretUTF8: 10,
            caretUTF16: 10,
            hashUTF16Range: NSRange(location: 9, length: 1)
        )
        XCTAssertFalse(model.replaceHashAliasWithLiteralBackslash(arm))
        XCTAssertEqual(textView.string, "jot idea #b")
    }

    func testHashAliasArmWithoutNativeBridgeIsInert() {
        let model = CapturePanelModel()
        let arm = CaptureHashAliasArm(
            draft: "jot idea #",
            hashUTF8: 9,
            caretUTF8: 10,
            caretUTF16: 10,
            hashUTF16Range: NSRange(location: 9, length: 1)
        )
        XCTAssertFalse(model.replaceHashAliasWithLiteralBackslash(arm))
    }
}
