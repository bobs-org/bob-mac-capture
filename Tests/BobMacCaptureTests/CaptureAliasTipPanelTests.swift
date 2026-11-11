import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureAliasTipPanelTests: XCTestCase {
    private let suiteName = "org.bobs.bob-mac-capture.tests.tips.\(UUID().uuidString)"
    private lazy var defaults = UserDefaults(suiteName: suiteName)!
    private var hostedWindows: [NSWindow] = []

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

    func testShiftTypedPercentShowsDirectiveMenuTip() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            debounceNanoseconds: 1_000_000_000
        )
        typeSigil("%", into: textView, model: model, modifiers: .shift)
        await waitUntil {
            model.completionResponse?.context == "directive"
                && model.presentedAliasTip?.id == CaptureAliasLesson.directiveMenu
        }

        XCTAssertEqual(model.completionResponse?.context, "directive")
        XCTAssertEqual(model.presentedAliasTip?.sigil, "%")
        XCTAssertEqual(model.presentedAliasTip?.keys, ["\\"])
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.directiveMenu]?.tipsShown,
            1,
            "dropped: \(model.aliasTipLedgerStore.load().dropped)"
        )
        XCTAssertTrue(
            (try String(contentsOf: recordURL)).contains(
                "argv=capture-rewrite --cursor 10 --format json -- Buy milk %"
            )
        )
    }

    func testTypingQueryBeforeTheRouteListOpensKeepsTheTip() async throws {
        let (model, textView) = try makeModel(
            recordURL: makeRecordURL(),
            debounceNanoseconds: 200_000_000
        )
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        insert("er", into: textView, model: model)

        await waitUntil {
            model.completionDraftSnapshotForTesting == "Buy milk @er"
                && model.presentedAliasTip?.id == CaptureAliasLesson.routeAfterText
        }

        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?.tipsShown,
            1
        )
        XCTAssertEqual(model.aliasTipLedgerStore.load().dropped, [:])
    }

    func testFilteringKeepsTheShownTipAnchoredToTheSigil() async throws {
        let (model, textView) = try makeModel(recordURL: makeRecordURL())
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil {
            model.completionVisible
                && model.presentedAliasTip?.id == CaptureAliasLesson.routeAfterText
        }

        insert("e", into: textView, model: model)
        await waitUntil {
            model.completionDraftSnapshotForTesting == "Buy milk @e"
                && model.presentedAliasTip?.id == CaptureAliasLesson.routeAfterText
        }

        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?.tipsShown,
            1
        )
        XCTAssertEqual(model.aliasTipLedgerStore.load().dropped, [:])
    }

    func testPreviousRouteListDoesNotBlockPickerTips() async throws {
        for (sigil, lessonID) in [
            (":", CaptureAliasLesson.linkAfterRoute),
            ("^", CaptureAliasLesson.blockIDAfterRoute),
        ] {
            defaults.removePersistentDomain(forName: suiteName)
            let recordURL = makeRecordURL()
            let (model, textView) = try makeModel(
                recordURL: recordURL,
                extra: [
                    "FAKE_BOB_ALIAS_TIP_ANCHOR": "1",
                    "FAKE_BOB_CAPTURE_COMPLETE_DELAY_SECONDS": "0.15",
                ],
                debounceNanoseconds: 0,
                text: "@file"
            )
            model.editorTextDidChange(cursorUTF8Offset: "@file".utf8.count)
            await waitUntil {
                model.completionDraftSnapshotForTesting == "@file" && model.completionVisible
            }
            XCTAssertNil(model.picker)

            typeSigil(sigil, into: textView, model: model, modifiers: .shift)
            await waitUntil {
                model.pickerVisible && model.presentedAliasTip?.id == lessonID
            }

            XCTAssertEqual(model.aliasTipLedgerStore.load().lessons[lessonID]?.tipsShown, 1)
            XCTAssertEqual(model.aliasTipLedgerStore.load().dropped, [:])
        }
    }

    func testEditingTheSigilAfterItShowsClearsTheTipRow() async throws {
        let (model, textView) = try makeModel(recordURL: makeRecordURL())
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil {
            model.completionVisible
                && model.presentedAliasTip?.id == CaptureAliasLesson.routeAfterText
        }

        restorePrefix("Buy milk ", into: textView, model: model)
        model.editorTextDidChange(cursorUTF8Offset: "Buy milk ".utf8.count)

        XCTAssertNil(model.presentedAliasTip)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?.tipsShown,
            1
        )
        XCTAssertEqual(model.aliasTipLedgerStore.load().dropped, [:])
    }

    func testFirstSettledAnalysisWithoutAnAnchoredSurfaceCountsUnanchored() async throws {
        let (model, textView) = try makeModel(
            recordURL: makeRecordURL(),
            debounceNanoseconds: 200_000_000
        )
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        insert(" ", into: textView, model: model)

        await waitUntil {
            model.aliasTipLedgerStore.load().dropped[AliasTipDropReason.unanchored.rawValue] == 1
        }

        XCTAssertNil(model.presentedAliasTip)
        XCTAssertNil(model.pendingAliasTipForTesting)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?.recent,
            [.miss]
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
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().dropped[AliasTipDropReason.lateReply.rawValue],
            1
        )
    }

    func testDismissedFirstSurfaceCannotReviveATipOnReopen() async throws {
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

        await waitUntil { model.completionVisible }
        model.dismissCompletion()
        XCTAssertFalse(model.completionVisible)
        FileManager.default.createFile(atPath: release.path, contents: Data())
        await waitUntil { !model.aliasTipInFlightForTesting }

        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        await waitUntil { model.completionVisible }

        XCTAssertNil(model.presentedAliasTip)
        XCTAssertNil(model.pendingAliasTipForTesting)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .recent,
            [.miss]
        )
    }

    func testSubmitBeforeReplyRetiresTipDisplay() async throws {
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
        await waitUntil { model.completionVisible }
        XCTAssertTrue(model.aliasTipInFlightForTesting)
        defer { FileManager.default.createFile(atPath: release.path, contents: Data()) }

        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: false)
        XCTAssertTrue(model.isSubmitting || model.inboxRouteChoiceVisible)
        FileManager.default.createFile(atPath: release.path, contents: Data())
        await waitUntil { !model.aliasTipInFlightForTesting }
        await waitUntil { !model.isSubmitting }

        XCTAssertNil(model.presentedAliasTip)
        XCTAssertNil(model.pendingAliasTipForTesting)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .recent,
            [.miss]
        )
    }

    func testHideShowCannotReviveAnOldTipReply() async throws {
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
        await waitUntil { model.completionVisible }
        XCTAssertTrue(model.aliasTipInFlightForTesting)
        defer { FileManager.default.createFile(atPath: release.path, contents: Data()) }

        model.prepareForDismissal()
        XCTAssertNil(model.presentedAliasTip)
        XCTAssertNil(model.pendingAliasTipForTesting)
        FileManager.default.createFile(atPath: release.path, contents: Data())
        model.prepareForPresentation()
        await waitUntil { model.completionVisible || !model.aliasTipInFlightForTesting }
        await waitUntil { !model.aliasTipInFlightForTesting }

        XCTAssertNil(model.presentedAliasTip)
        XCTAssertNil(model.pendingAliasTipForTesting)
        XCTAssertEqual(textView.string, "Buy milk @")
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .recent,
            nil
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
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().dropped[AliasTipDropReason.sigilEdited.rawValue],
            1
        )
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
        model.aliasTipTimeout = 4
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

    func testExplicitNullCountsIneligibleWithoutDisablingTheTipLane() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            extra: ["FAKE_BOB_ALIAS_TIP": "null"]
        )
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil { !model.aliasTipInFlightForTesting }
        XCTAssertEqual(model.aliasTipLedgerStore.load().ineligible["@"], 1)

        restorePrefix("Buy milk ", into: textView, model: model)
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil { !model.aliasTipInFlightForTesting }
        XCTAssertEqual(captureRewriteCount(in: recordURL, draft: "Buy milk @"), 2)
        XCTAssertEqual(model.aliasTipLedgerStore.load().ineligible["@"], 2)
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
        XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.routeAfterText), 0)
        XCTAssertTrue(
            model.aliasTipSessionForTesting.escapedLessons.contains(
                CaptureAliasLesson.routeAfterText
            )
        )
    }

    func testNativeUndoAfterLaterTypingWithdrawsOnlyTheUndoneAlias() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeHostedModel(recordURL: recordURL)
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "."),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        insert(".", into: textView, model: model)
        await waitUntil { textView.string == "Buy milk @" }
        XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.routeAfterText), 1)

        try await Task.sleep(nanoseconds: 50_000_000)
        insert(" later", into: textView, model: model)
        XCTAssertEqual(textView.string, "Buy milk @ later")
        XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.routeAfterText), 1)

        textView.undoManager?.undo()
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        XCTAssertEqual(textView.string, "Buy milk @")
        XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.routeAfterText), 1)

        textView.undoManager?.undo()
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        XCTAssertEqual(textView.string, "Buy milk .")
        XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.routeAfterText), 0)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .recent,
            []
        )

        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.routeAfterText), 0)
    }

    func testChangedSeparatorReplyDoesNotDisableTheNextTipRequest() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeHostedModel(
            recordURL: recordURL,
            extra: ["FAKE_BOB_SEPARATOR_TOGGLE_REPLY": "1"],
            text: "@cash:task"
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^", modifiers: .shift),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        typeSigil("^", into: textView, model: model, modifiers: .shift)
        await waitUntil { textView.string == "@cash^task" }
        await waitUntil { !model.aliasTipInFlightForTesting }
        XCTAssertEqual(model.plainDraft, "@cash^task")
        XCTAssertGreaterThanOrEqual(
            captureRewriteCount(in: recordURL, draft: "@cash:task^"),
            2
        )

        textView.undoManager?.undo()
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        XCTAssertEqual(textView.string, "@cash:task^")

        restorePrefix("Buy milk ", into: textView, model: model)
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil {
            model.completionVisible
                && model.presentedAliasTip?.id == CaptureAliasLesson.routeAfterText
        }
        XCTAssertEqual(
            captureRewriteCount(in: recordURL, draft: "Buy milk @"),
            1
        )
    }

    func testAliasAdoptionsCountWithTipsOnAndOff() async throws {
        for tipsEnabled in [true, false] {
            let (model, textView) = try makeHostedModel(recordURL: makeRecordURL())
            model.aliasTipLedgerStore.reset()
            model.typingTipsEnabled = tipsEnabled
            CapturePanelController.noteSeparatorToggleIntentIfEligible(
                event: keyEvent(characters: "."),
                firstResponder: textView,
                model: model,
                modalFieldActive: false
            )
            insert(".", into: textView, model: model)
            await waitUntil { textView.string == "Buy milk @" }
            XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.routeAfterText), 1)
        }
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
        XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.routeAfterText), 1)
        XCTAssertTrue(model.restoreRelationEqualsOpener(key: " "))
        XCTAssertEqual(textView.string, "Buy milk . ")
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.routeAfterText]?
                .recent,
            []
        )
        XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.routeAfterText), 0)
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
        XCTAssertEqual(weeklyHitCount(model, id: CaptureAliasLesson.hashMenu), 0)
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

    func testTypedSigilTriggersIncludeThePickerLessons() {
        XCTAssertEqual(
            CapturePanelModel.typedSigilTriggers,
            Set(["@", "#", "%", "^", ":", "+", "~", "&", "*"])
        )
    }

    func testPickerLessonsAreAdmittedOnOpenAndLateRepliesDrop() throws {
        let pickerLessons = CaptureAliasLesson.all.filter { $0.host == .picker }
        XCTAssertEqual(pickerLessons.count, 9)

        for lesson in pickerLessons {
            defaults.removePersistentDomain(forName: suiteName)
            let tip = pickerTip(for: lesson)
            let draft = tip.sigil
            let earlyRecord = makeRecordURL()
            let (early, _) = try makeModel(recordURL: earlyRecord, text: draft)
            let earlyClient = try processClient(recordURL: earlyRecord)
            early.applyAliasTipRewrite(
                tipResponse(tip, draft: draft),
                draft: draft,
                sigil: tip.sigil,
                generation: early.aliasTipGenerationForTesting,
                processClient: earlyClient
            )
            XCTAssertEqual(early.pendingAliasTipForTesting?.id, lesson.id)
            early.dismissCompletion(preservePendingAliasTip: true)
            openPicker(early, draft: draft)
            XCTAssertEqual(early.presentedAliasTip?.id, lesson.id)
            XCTAssertNil(early.pendingAliasTipForTesting)
            XCTAssertTrue(early.aliasTipSessionForTesting.didShowTip)
            early.updatePickerFilter("no match")
            XCTAssertEqual(early.presentedAliasTip?.id, lesson.id)
            XCTAssertEqual(
                early.aliasTipLedgerStore.load().lessons[lesson.id]?.tipsShown,
                1
            )

            defaults.removePersistentDomain(forName: suiteName)
            let lateRecord = makeRecordURL()
            let (late, _) = try makeModel(recordURL: lateRecord, text: draft)
            let lateClient = try processClient(recordURL: lateRecord)
            openPicker(late, draft: draft)
            late.applyAliasTipRewrite(
                tipResponse(tip, draft: draft),
                draft: draft,
                sigil: tip.sigil,
                generation: late.aliasTipGenerationForTesting,
                processClient: lateClient
            )
            XCTAssertNil(late.presentedAliasTip)
            XCTAssertNil(late.pendingAliasTipForTesting)
            XCTAssertEqual(
                late.aliasTipLedgerStore.load().lessons[lesson.id]?.recent,
                [.miss]
            )
        }
    }

    func testListThenPickerSequenceShowsAtMostOneTip() async throws {
        let recordURL = makeRecordURL()
        let (model, textView) = try makeModel(
            recordURL: recordURL,
            debounceNanoseconds: 200_000_000
        )
        typeSigil("@", into: textView, model: model, modifiers: .shift)
        await waitUntil {
            model.completionVisible
                && model.presentedAliasTip?.id == CaptureAliasLesson.routeAfterText
        }
        model.dismissCompletion()

        let pickerTip = pickerTip(
            id: CaptureAliasLesson.blockIDAfterRoute,
            sigil: "^",
            key: "."
        )
        restorePrefix(pickerTip.sigil, into: textView, model: model)
        let pickerClient = try processClient(recordURL: recordURL)
        model.applyAliasTipRewrite(
            tipResponse(pickerTip, draft: pickerTip.sigil),
            draft: pickerTip.sigil,
            sigil: pickerTip.sigil,
            generation: model.aliasTipGenerationForTesting,
            processClient: pickerClient
        )
        openPicker(model, draft: pickerTip.sigil)

        XCTAssertNil(model.presentedAliasTip)
        XCTAssertTrue(model.aliasTipSessionForTesting.didShowTip)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[CaptureAliasLesson.blockIDAfterRoute]?
                .tipsShown,
            0
        )
    }

    func testPickerTipYieldsBeforeRowsOnShortScreen() throws {
        let draft = "^"
        let tip = pickerTip(
            id: CaptureAliasLesson.blockIDAfterRoute,
            sigil: draft,
            key: "."
        )
        let (model, _) = try makeModel(recordURL: makeRecordURL(), text: draft)
        model.availableScreenHeight = 450
        let chrome: CGFloat = 120
        let screenLimit = 450 - 2 * CapturePanelLayout.panelScreenMargin
        XCTAssertLessThanOrEqual(
            chrome + CapturePickerHeightPolicy(visibleRowBudget: 4).idealHeight,
            screenLimit
        )
        XCTAssertFalse(model.aliasTipFitsPickerPanelBudget(visibleRowBudget: 4))
        model.installPendingAliasTipForPreviews(tip, draft: draft)

        openPicker(model, draft: draft)

        XCTAssertNil(model.presentedAliasTip)
        XCTAssertEqual(model.picker?.visibleRowBudget, 4)
        XCTAssertEqual(
            model.aliasTipLedgerStore.load().lessons[tip.id]?.recent,
            [.miss]
        )
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

    private func pickerTip(for lesson: CaptureAliasLesson) -> CaptureSigilAliasTip {
        let sigilAndKey: (sigil: String, key: String)
        switch lesson.id {
        case CaptureAliasLesson.blockIDAfterRoute, CaptureAliasLesson.moveBulletCaret:
            sigilAndKey = ("^", ".")
        case CaptureAliasLesson.linkAfterRoute, CaptureAliasLesson.taskLinkItem,
             CaptureAliasLesson.moveBulletColon:
            sigilAndKey = (":", ";")
        case CaptureAliasLesson.parentTask:
            sigilAndKey = ("+", ",")
        case CaptureAliasLesson.relation:
            sigilAndKey = ("~", "=")
        case CaptureAliasLesson.dependency:
            sigilAndKey = ("&", ".")
        case CaptureAliasLesson.blockedTask:
            sigilAndKey = ("*", ";")
        default:
            XCTFail("Expected a picker lesson: \(lesson.id)")
            sigilAndKey = ("^", ".")
        }
        return pickerTip(id: lesson.id, sigil: sigilAndKey.sigil, key: sigilAndKey.key)
    }

    private func pickerTip(
        id: String,
        sigil: String,
        key: String
    ) -> CaptureSigilAliasTip {
        CaptureSigilAliasTip(
            id: id,
            sigil: sigil,
            keys: [key],
            range: CaptureRange(start: 0, end: sigil.utf8.count),
            positionPhrase: "after a word"
        )
    }

    private func tipResponse(
        _ tip: CaptureSigilAliasTip,
        draft: String
    ) -> CaptureRewriteResponse {
        CaptureRewriteResponse(
            ok: true,
            schemaVersion: 1,
            input: draft,
            text: draft,
            changed: false,
            cursor: draft.utf8.count,
            sigilAliasTip: tip,
            reportsSigilAliasTips: true
        )
    }

    private func openPicker(_ model: CapturePanelModel, draft: String) {
        let candidates: [CaptureCompletionCandidate] = []
        model.presentPicker(
            source: .activeTask,
            index: .activeTask(ActiveTaskPickerIndex(candidates: candidates)),
            candidates: candidates,
            warnings: [],
            draft: draft,
            range: CaptureRange(start: 0, end: draft.utf8.count),
            restoreCursor: draft.utf8.count,
            query: "",
            snapshotIsPartial: false
        )
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
        let needle = "argv=capture-rewrite --cursor \(draft.utf8.count) --format json -- \(draft)"
        return record.components(separatedBy: needle).count - 1
    }

    private func weeklyHitCount(_ model: CapturePanelModel, id: String) -> Int {
        model.aliasTipLedgerStore.load().weeks.values
            .compactMap { $0[id]?.hits }
            .reduce(0, +)
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
