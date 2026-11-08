import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureRelationEqualsAliasTests: XCTestCase {
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

    private func dashEvent(
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(keyCode: 27, characters: "-", modifiers: modifiers, isRepeat: isRepeat)
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

    private func tildeEvent(timestamp: TimeInterval = 0) -> NSEvent {
        keyEvent(
            keyCode: 50,
            characters: "~",
            modifiers: .shift,
            timestamp: timestamp
        )
    }

    private func spaceEvent(isRepeat: Bool = false) -> NSEvent {
        keyEvent(keyCode: 49, characters: " ", isRepeat: isRepeat)
    }

    private func escapeEvent() -> NSEvent {
        keyEvent(keyCode: 53, characters: "")
    }

    private func returnEvent() -> NSEvent {
        keyEvent(keyCode: 36, characters: "\r")
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
        panel.contentView = textView
        XCTAssertTrue(panel.makeFirstResponder(textView))
        controller.replayedKeyForTesting = { event in
            textView.insertText(
                event.characters ?? "",
                replacementRange: textView.selectedRange()
            )
            model.plainDraft = textView.string
            let caretUTF8 =
                utf8Offset(
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

    private func keepTypeAheadHoldOpenForTest(_ controller: CapturePanelController) {
        controller.typeAheadNow = { 0 }
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

    /// State dump for an alias that never opened its picker, so a rare CI
    /// timeout says whether the rewrite, parse, or completion went missing.
    private func aliasOpenDetail(
        textView: NSTextView,
        model: CapturePanelModel,
        recordURL: URL
    ) -> String {
        let record = (try? String(contentsOf: recordURL)) ?? "<no record>"
        let argv = record.split(separator: "\n").filter { $0.hasPrefix("argv=") }
        return "; text=\(textView.string.debugDescription)"
            + " draft=\(model.plainDraft.debugDescription)"
            + " picker=\(String(describing: model.picker?.source))"
            + " filter=\(String(describing: model.picker?.filterText))"
            + " rewriteInFlight=\(model.rewriteInFlightForTesting)"
            + " argv=\(argv)"
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
        XCTAssertNotNil(typeKey(equalsEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Fix it ~" && model.picker?.source == .linksTo
                && model.picker?.filterText.isEmpty == true
        } detail: {
            aliasOpenDetail(textView: textView, model: model, recordURL: recordURL)
        }
        return (model, controller, textView, panel, recordURL)
    }

    func testEqualsAliasOpensLinksToAndCallsRewriteBeforeCompletion() async throws {
        let (model, _, _, panel, recordURL) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertEqual(model.picker?.draftSnapshot, "Fix it ~")
        XCTAssertEqual(model.picker?.replacementRange.start, 7)
        let record = try String(contentsOf: recordURL)
        let rewrite = try XCTUnwrap(record.range(of: "argv=capture-rewrite --cursor 8 --format json -- Fix it ="))
        let complete = try XCTUnwrap(record.range(of: "argv=capture-complete --all-tasks --cursor 8 --format json -- Fix it ~"))
        XCTAssertLessThan(rewrite.lowerBound, complete.lowerBound)
    }

    func testSpaceRestoresEqualsAndUndoRestoresTheAliasDraft() async throws {
        let (model, controller, textView, panel, _) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertNil(typeKey(spaceEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Fix it = ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.pickerChip)
        XCTAssertNil(model.equalsGestureArm)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Fix it ~")
    }

    func testEscapeRestoresEqualsInsteadOfShowingPickerChip() async throws {
        let (model, controller, textView, panel, _) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertNil(typeKey(escapeEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Fix it =")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.pickerChip)
    }

    func testFastSpaceRestoresEqualsBeforeTheCompletionReplyOpens() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_RELATION_EQUALS_COMPLETE_DELAY_SECONDS": "0.4"]
        )

        XCTAssertNotNil(typeKey(equalsEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Fix it ~" && model.equalsGestureArm?.isOpener == true
                && !model.pickerVisible
        }
        XCTAssertNil(typeKey(spaceEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Fix it = ")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(model.pickerVisible)
    }

    func testOlderBobLeavesEqualsLiteralWithoutOpeningPicker() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_RELATION_EQUALS_UNCHANGED": "1"]
        )

        XCTAssertNotNil(typeKey(equalsEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Fix it ="
                && (try? String(contentsOf: recordURL))?.contains("argv=capture-rewrite") == true
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.equalsGestureArm)
    }

    func testSpaceDashStaysLiteralAndDoesNotOpenLinksTo() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Fix it -"
                && (try? String(contentsOf: recordURL))?.contains("argv=capture-rewrite") == true
        }
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.equalsGestureArm)
    }

    func testPastSegmentDashAliasIsUngatedAndUndoRestoresTheDash() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        keepTypeAheadHoldOpenForTest(controller)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PAST_SEGMENT_REWRITE_DELAY_SECONDS": "0.15"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "x=2~" }
        XCTAssertEqual(model.plainDraft, "x=2~")
        XCTAssertNil(model.equalsGestureArm)
        XCTAssertTrue(try String(contentsOf: recordURL).contains(
            "argv=capture-rewrite --cursor 4 --format json -- x=2-"
        ))

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "x=2-")
    }

    func testFastReturnWaitsForPastSegmentDashRewriteBeforeSubmit() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        keepTypeAheadHoldOpenForTest(controller)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PAST_SEGMENT_REWRITE_DELAY_SECONDS": "0.15"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(controller.routeKeyDown(returnEvent()))
        // The native rewrite may echo the still-visible input draft before
        // Bob's replacement reaches the model mirror. That no-change echo
        // must not cancel the Return waiting on the rewrite.
        model.editorTextDidChange(cursorUTF8Offset: 4)
        await waitUntil { textView.string == "x=2~" }
        // SwiftUI can deliver a delayed caret echo from immediately before
        // the native rewrite; it must not cancel the Return already waiting.
        model.editorSelectionDidChange(cursorUTF8Offset: 4)
        model.editorSelectionDidChange(cursorUTF8Offset: 3)
        model.editorSelectionDidChange(cursorUTF8Offset: 3)
        await waitUntil {
            !model.isSubmitting
                && ((try? String(contentsOf: recordURL))?.contains("argv=capture --format json") == true)
        }
        XCTAssertEqual(textView.string, "x=2~")
        XCTAssertNil(model.relationCapabilityWarning)
        let record = try String(contentsOf: recordURL)
        let writes = record.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("argv=capture --format json") && !$0.contains("--dry-run") }
        guard writes.count == 1, let write = writes.first else {
            XCTFail("Expected one capture write after the segment rewrite:\n\(record)")
            return
        }
        XCTAssertTrue(write.hasSuffix("-- x=2~"), record)
        XCTAssertFalse(write.hasSuffix("-- x=2-"), record)
    }

    func testTypeAheadReplaysEditKeysAndReturnAfterDashRewrite() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        keepTypeAheadHoldOpenForTest(controller)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PAST_SEGMENT_REWRITE_DELAY_SECONDS": "0.05"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(
            typeKey(
                keyEvent(keyCode: 20, characters: "3", timestamp: 1.25),
                into: textView,
                model: model,
                controller: controller
            ))
        XCTAssertNil(controller.routeKeyDown(returnEvent()))
        XCTAssertEqual(textView.string, "x=2-")

        await waitUntil {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return textView.string == "x=2~3"
                && record.contains("argv=capture --format json")
        } detail: {
            aliasOpenDetail(textView: textView, model: model, recordURL: recordURL)
                + " warning=\(String(describing: model.relationCapabilityWarning))"
                + " submitting=\(model.isSubmitting)"
        }
        XCTAssertNil(model.relationCapabilityWarning)
        let record = try String(contentsOf: recordURL)
        let writes = record.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("argv=capture --format json") && !$0.contains("--dry-run") }
        XCTAssertEqual(writes.count, 1, record)
        XCTAssertTrue(writes.first?.hasSuffix("-- x=2~3") == true, record)
    }

    func testNoChangeReplyReplaysLiteralEditAndReturn() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        keepTypeAheadHoldOpenForTest(controller)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PAST_SEGMENT_REWRITE_UNCHANGED": "1"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(
            typeKey(
                keyEvent(keyCode: 20, characters: "3"),
                into: textView,
                model: model,
                controller: controller
            ))
        XCTAssertNil(controller.routeKeyDown(returnEvent()))

        await waitUntil {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return textView.string == "x=2-3"
                && record.contains("argv=capture --format json")
        }
        let record = try String(contentsOf: recordURL)
        let writes = record.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("argv=capture --format json") && !$0.contains("--dry-run") }
        XCTAssertEqual(writes.count, 1, record)
        XCTAssertTrue(writes.first?.hasSuffix("-- x=2-3") == true, record)
    }

    func testRewriteFailureReplaysEditsDropsReturnAndAnnouncesRetry() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_FAIL": "1"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(
            typeKey(
                keyEvent(keyCode: 20, characters: "3"),
                into: textView,
                model: model,
                controller: controller
            ))
        XCTAssertNil(controller.routeKeyDown(returnEvent()))

        await waitUntil { model.statusText == "Bob did not answer; press Return again" }
        XCTAssertEqual(textView.string, "x=2-3")
        let record = (try? String(contentsOf: recordURL)) ?? ""
        XCTAssertFalse(
            record.split(separator: "\n").contains {
                $0.hasPrefix("argv=capture --format json") && !$0.contains("--dry-run")
            }, record)
    }

    func testDeadlineKeepsAliasLiteralAndDropsBufferedReturn() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        var now: TimeInterval = 10
        controller.typeAheadNow = { now }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(
            typeKey(
                keyEvent(keyCode: 20, characters: "3"),
                into: textView,
                model: model,
                controller: controller
            ))
        XCTAssertNil(controller.routeKeyDown(returnEvent()))

        now = 10.21
        controller.expireTypeAheadHoldForTesting()
        XCTAssertEqual(textView.string, "x=2-3")
        XCTAssertEqual(model.statusText, "Bob did not answer; press Return again")
        XCTAssertFalse(model.isSubmitting)
    }

    func testDeadlineWithNoBufferedKeysLeavesRewriteRunning() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        var now: TimeInterval = 10
        controller.typeAheadNow = { now }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PAST_SEGMENT_REWRITE_DELAY_SECONDS": "0.05"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        now = 10.21
        controller.expireTypeAheadHoldForTesting()

        await waitUntil { textView.string == "x=2~" }
        XCTAssertEqual(model.plainDraft, "x=2~")
    }

    func testReplayedBackslashRoutesOnceAndKeepsItsOriginalTimestamp() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        keepTypeAheadHoldOpenForTest(controller)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PAST_SEGMENT_REWRITE_DELAY_SECONDS": "0.05"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(
            typeKey(
                keyEvent(keyCode: 42, characters: "\\", timestamp: 42.75),
                into: textView,
                model: model,
                controller: controller
            ))

        await waitUntil {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return textView.string == "x=2~\\"
                && record.split(separator: "\n").filter {
                    $0.hasPrefix("argv=capture-rewrite")
                }.count == 2
        }
        XCTAssertEqual(controller.replayedKeyRouteCountForTesting, 1)
        XCTAssertEqual(controller.replayedKeyTimestampsForTesting, [42.75])
    }

    func testLeavingTheDraftEditorFlushesHeldEditsBeforeFocusMoves() throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(
            typeKey(
                keyEvent(keyCode: 20, characters: "3"),
                into: textView,
                model: model,
                controller: controller
            ))
        XCTAssertNil(controller.routeKeyDown(returnEvent()))

        XCTAssertTrue(panel.makeFirstResponder(nil))
        XCTAssertEqual(textView.string, "x=2-3")
        XCTAssertEqual(model.statusText, "Bob did not answer; press Return again")
        XCTAssertFalse(model.isSubmitting)
    }

    func testRapidSecondDashCannotReceiveTheFirstRewriteReply() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PAST_SEGMENT_REWRITE_DELAY_SECONDS": "0.25"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "x=2-")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(textView.string, "x=2--")
        XCTAssertEqual(model.plainDraft, "x=2--")
    }

    func testFastDashCountAndEndEdgeStayCurrentWhenReturnArrives() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "x=2")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PAST_SEGMENT_REWRITE_DELAY_SECONDS": "0.25"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(typeKey(
            keyEvent(keyCode: 0, characters: "1"),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertNil(typeKey(
            keyEvent(keyCode: 0, characters: "+"),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertNil(controller.routeKeyDown(returnEvent()))
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(textView.string, "x=2-1+")
        XCTAssertEqual(model.plainDraft, "x=2-1+")
        let record = (try? String(contentsOf: recordURL)) ?? ""
        XCTAssertFalse(record.split(separator: "\n").contains {
            $0.hasPrefix("argv=capture --format json") && !$0.contains("--dry-run")
        }, record)
    }

    func testRouterRestoresOnlySpaceAndEscapeForTheArmedEmptyLinksToFilter() {
        let router = CaptureKeyCommandRouter()
        var armed = CaptureKeyRoutingContext()
        armed.pickerSourceIsRelation = true
        armed.pickerVisible = true
        armed.pickerFilterIsEmpty = true
        armed.relationEqualsOpenerArmed = true
        XCTAssertEqual(
            router.command(for: spaceEvent(), context: armed),
            .restoreRelationEqualsOpener(" ")
        )
        XCTAssertEqual(
            router.command(for: escapeEvent(), context: armed),
            .restoreRelationEqualsOpener("")
        )
        XCTAssertEqual(
            router.command(for: equalsEvent(), context: armed),
            .flipRelationDirection
        )
        XCTAssertEqual(
            router.command(for: spaceEvent(), context: CaptureKeyRoutingContext(
                pickerSourceIsRelation: true,
                pickerVisible: true,
                pickerFilterIsEmpty: false,
                relationEqualsOpenerArmed: true
            )),
            nil
        )
        XCTAssertEqual(
            router.command(for: spaceEvent(isRepeat: true), context: armed),
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

    func testEditorRaceWindowRestoresEqualsBeforePickerVisibility() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(relationEqualsOpenerArmed: true)
        XCTAssertEqual(
            router.command(for: spaceEvent(), context: context),
            .restoreRelationEqualsOpener(" ")
        )
        XCTAssertEqual(router.command(for: equalsEvent(), context: context), nil)
    }

    private func openTimestampedAlias(
        firstTimestamp: TimeInterval
    ) async throws -> (
        CapturePanelModel,
        CapturePanelController,
        NSTextView,
        NSPanel
    ) {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        model.processClient = try processClient(recordURL: recordURL)
        XCTAssertNotNil(typeKey(
            equalsEvent(timestamp: firstTimestamp),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil {
            textView.string == "Fix it ~" && model.picker?.source == .linksTo
                && model.picker?.filterText.isEmpty == true
        } detail: {
            aliasOpenDetail(textView: textView, model: model, recordURL: recordURL)
        }
        return (model, controller, textView, panel)
    }

    func testFastSecondEqualsUndoesOpenerAfterReply() async throws {
        let (model, controller, textView, panel) = try await openTimestampedAlias(
            firstTimestamp: 1.0
        )
        defer { panel.orderOut(nil) }
        XCTAssertEqual(model.equalsGestureArm?.isOpener, true)

        XCTAssertNil(controller.routeKeyDown(equalsEvent(timestamp: 1.350)))
        XCTAssertEqual(textView.string, "Fix it =")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.picker)
        XCTAssertNil(model.equalsGestureArm)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Fix it ~")
    }

    func testSlowSecondEqualsFlipsAfterReply() async throws {
        let (model, controller, _, panel) = try await openTimestampedAlias(
            firstTimestamp: 1.0
        )
        defer { panel.orderOut(nil) }

        // 351 ms after the first key is past the window: an ordinary flip.
        XCTAssertNil(controller.routeKeyDown(equalsEvent(timestamp: 1.351)))
        XCTAssertEqual(model.plainDraft, "Fix it ~~")
        XCTAssertEqual(model.equalsGestureArm?.isOpener, false)
        await waitUntil { model.picker?.source == .linkedFrom }
        XCTAssertTrue(model.pickerVisible)
    }

    func testFastDoubleEqualsBeforeReplyCollapsesToOne() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
        )

        XCTAssertNotNil(typeKey(
            equalsEvent(timestamp: 1.0),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertEqual(textView.string, "Fix it =")
        XCTAssertNotNil(typeKey(
            equalsEvent(timestamp: 1.1),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertEqual(textView.string, "Fix it ==")

        // The probe re-asks Bob about the first draft; the alias answer
        // collapses the pair without ever opening the picker.
        await waitUntil {
            textView.string == "Fix it =" && model.equalsProbe == nil
        }
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.equalsGestureArm)
        let record = try String(contentsOf: recordURL)
        let asks = record.split(separator: "\n").filter {
            $0.hasPrefix("argv=capture-rewrite") && $0.hasSuffix("-- Fix it =")
        }
        XCTAssertEqual(asks.count, 2)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Fix it ==")
    }

    func testFastEqualsTildeBeforeReplyProducesLinkedFrom() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
        )

        XCTAssertNotNil(typeKey(
            equalsEvent(timestamp: 1.0),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertNotNil(typeKey(
            tildeEvent(timestamp: 1.1),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertEqual(textView.string, "Fix it =~")

        // The reliable Linked From spelling at any speed: `=~` becomes `~~`
        // and arms the record like the slow flip path.
        await waitUntil {
            textView.string == "Fix it ~~" && model.equalsProbe == nil
        }
        XCTAssertEqual(model.equalsGestureArm?.isOpener, false)
        XCTAssertEqual(model.equalsGestureArm?.preDraft, "Fix it ")
    }

    func testTripleEqualsGivesDoubleEquals() async throws {
        let (model, controller, textView, panel) = try await openTimestampedAlias(
            firstTimestamp: 1.0
        )
        defer { panel.orderOut(nil) }

        XCTAssertNil(controller.routeKeyDown(equalsEvent(timestamp: 1.1)))
        XCTAssertEqual(textView.string, "Fix it =")

        // The undo consumed the record, so the third `=` types natively and
        // no alias fires: `===` gives `==`.
        XCTAssertNotNil(typeKey(
            equalsEvent(timestamp: 1.2),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil { textView.string == "Fix it ==" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(textView.string, "Fix it ==")
        XCTAssertFalse(model.pickerVisible)
    }

    func testTildeFlipThenFastEqualsRestoresTildeEquals() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "New task ~")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)

        XCTAssertNotNil(typeKey(
            equalsEvent(timestamp: 1.0),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil { textView.string == "New task ~~" }
        XCTAssertEqual(model.equalsGestureArm?.isOpener, false)

        // `~=` became `~~`; a fast `=` undoes the flip back to `~=`.
        XCTAssertNil(controller.routeKeyDown(equalsEvent(timestamp: 1.1)))
        XCTAssertEqual(textView.string, "New task ~=")
        XCTAssertNil(model.equalsGestureArm)
    }

    func testTildeFlipFastEqualsAfterPickerRestoresTildeEquals() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "New task ~")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)

        XCTAssertNotNil(typeKey(
            equalsEvent(timestamp: 1.0),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil {
            textView.string == "New task ~~" && model.picker?.source == .linkedFrom
        }
        XCTAssertEqual(model.equalsGestureArm?.isOpener, false)

        XCTAssertNil(controller.routeKeyDown(equalsEvent(timestamp: 1.1)))
        XCTAssertEqual(textView.string, "New task ~=")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.equalsGestureArm)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "New task ~~")
    }

    func testEqualsGestureGuardsRepeatMarkedTextAndZeroTimestamps() {
        let model = CapturePanelModel()
        model.plainDraft = "Fix it ~"
        model.equalsGestureArm = CaptureEqualsGestureArm(
            surface: .editor,
            firstTimestamp: 1.0,
            isOpener: true,
            preDraft: "Fix it ",
            preCaretUTF8: 7,
            postDraft: "Fix it ~",
            postCaretUTF8: 8,
            pickerSnapshot: nil
        )
        XCTAssertEqual(
            model.equalsGestureSecondEqualsSurface(
                timestamp: 1.1,
                isRepeat: false,
                markedText: false
            ),
            .editor
        )
        XCTAssertNil(model.equalsGestureSecondEqualsSurface(
            timestamp: 0,
            isRepeat: false,
            markedText: false
        ))
        XCTAssertNil(model.equalsGestureSecondEqualsSurface(
            timestamp: 0.1,
            isRepeat: false,
            markedText: false
        ))
        XCTAssertNil(model.equalsGestureSecondEqualsSurface(
            timestamp: 1.1,
            isRepeat: true,
            markedText: false
        ))
        XCTAssertNil(model.equalsGestureSecondEqualsSurface(
            timestamp: 1.1,
            isRepeat: false,
            markedText: true
        ))
        XCTAssertNil(model.equalsGestureSecondEqualsSurface(
            timestamp: 1.351,
            isRepeat: false,
            markedText: false
        ))
    }

    func testRouterFastEqualsUndoCommand() {
        let router = CaptureKeyCommandRouter()
        var armed = CaptureKeyRoutingContext()
        armed.equalsGestureFastSecond = true
        XCTAssertEqual(
            router.command(for: equalsEvent(), context: armed),
            .undoEqualsGestureAndTypeLiteral
        )
        // `~` never takes the undo path.
        XCTAssertNil(router.command(for: tildeEvent(), context: armed))
        // Repeats fall through to the ordinary path.
        var repeating = armed
        repeating.keyIsRepeat = true
        XCTAssertNil(router.command(for: equalsEvent(), context: repeating))
        XCTAssertNil(router.command(
            for: equalsEvent(isRepeat: true),
            context: armed
        ))
        // Without a live record the key passes through natively.
        XCTAssertNil(router.command(
            for: equalsEvent(),
            context: CaptureKeyRoutingContext()
        ))
    }
}
