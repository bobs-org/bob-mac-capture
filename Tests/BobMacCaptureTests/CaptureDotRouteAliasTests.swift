import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Fast `..` escape for the `.` → `@` route alias, driven through the real
/// `routeKeyDown` with a hosted panel and the live editor as first responder.
/// Modeled on `CaptureRelationEqualsAliasTests` (keyCode 47 for `.`).
@MainActor
final class CaptureDotRouteAliasTests: XCTestCase {
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
        keyEvent(
            keyCode: 47,
            characters: ".",
            modifiers: modifiers,
            timestamp: timestamp,
            isRepeat: isRepeat
        )
    }

    private func equalsEvent(timestamp: TimeInterval = 0) -> NSEvent {
        keyEvent(keyCode: 24, characters: "=", timestamp: timestamp)
    }

    private func spaceEvent(isRepeat: Bool = false) -> NSEvent {
        keyEvent(keyCode: 49, characters: " ", isRepeat: isRepeat)
    }

    private func escapeEvent() -> NSEvent {
        keyEvent(keyCode: 53, characters: "")
    }

    private func downEvent() -> NSEvent {
        keyEvent(keyCode: 125, characters: "")
    }

    private func upEvent() -> NSEvent {
        keyEvent(keyCode: 126, characters: "")
    }

    private func controlNEvent() -> NSEvent {
        keyEvent(keyCode: 45, characters: "n", modifiers: .control)
    }

    private func controlPEvent() -> NSEvent {
        keyEvent(keyCode: 35, characters: "p", modifiers: .control)
    }

    private func xEvent() -> NSEvent {
        keyEvent(keyCode: 7, characters: "x")
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

    private func aliasOpenDetail(
        textView: NSTextView,
        model: CapturePanelModel,
        recordURL: URL
    ) -> String {
        let record = (try? String(contentsOf: recordURL)) ?? "<no record>"
        let argv = record.split(separator: "\n").filter { $0.hasPrefix("argv=") }
        return "; text=\(textView.string.debugDescription)"
            + " draft=\(model.plainDraft.debugDescription)"
            + " completion=\(String(describing: model.completionResponse?.context))"
            + " completionVisible=\(model.completionVisible)"
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
        let (model, controller, textView, panel) = makeHostedEditor(text: "Buy milk ")
        model.processClient = try processClient(recordURL: recordURL)
        XCTAssertNotNil(typeKey(dotEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Buy milk @" && model.completionVisible
        } detail: {
            aliasOpenDetail(textView: textView, model: model, recordURL: recordURL)
        }
        return (model, controller, textView, panel, recordURL)
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
        let (model, controller, textView, panel) = makeHostedEditor(text: "Buy milk ")
        model.processClient = try processClient(recordURL: recordURL)
        XCTAssertNotNil(typeKey(
            dotEvent(timestamp: firstTimestamp),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil {
            textView.string == "Buy milk @" && model.completionVisible
        } detail: {
            aliasOpenDetail(textView: textView, model: model, recordURL: recordURL)
        }
        return (model, controller, textView, panel)
    }

    func testDotAliasAppliesAndOpensRouteList() async throws {
        let (model, _, _, panel, recordURL) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertEqual(model.completionResponse?.context, "route")
        XCTAssertEqual(model.equalsGestureArm?.key, ".")
        XCTAssertEqual(model.equalsGestureArm?.sigil, "@")
        XCTAssertEqual(model.equalsGestureArm?.isOpener, true)
        let record = try String(contentsOf: recordURL)
        let rewrite = try XCTUnwrap(record.range(of: "argv=capture-rewrite --cursor 10 --format json -- Buy milk ."))
        let complete = try XCTUnwrap(record.range(of: "argv=capture-complete --all-tasks --cursor 10 --format json -- Buy milk @"))
        XCTAssertLessThan(rewrite.lowerBound, complete.lowerBound)
    }

    func testSpaceRestoresDotAndUndoRestoresTheAliasDraft() async throws {
        let (model, controller, textView, panel, _) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertNil(typeKey(spaceEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Buy milk . ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 11, length: 0))
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.equalsGestureArm)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Buy milk @")
    }

    func testEscapeRestoresDotInsteadOfLeavingTheList() async throws {
        let (model, controller, textView, panel, _) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertNil(typeKey(escapeEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Buy milk .")
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.equalsGestureArm)
    }

    func testFastSecondDotUndoesOpenerAfterReply() async throws {
        let (model, controller, textView, panel) = try await openTimestampedAlias(
            firstTimestamp: 1.0
        )
        defer { panel.orderOut(nil) }
        XCTAssertEqual(model.equalsGestureArm?.isOpener, true)

        XCTAssertNil(controller.routeKeyDown(dotEvent(timestamp: 1.350)))
        XCTAssertEqual(textView.string, "Buy milk .")
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.equalsGestureArm)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Buy milk @")
    }

    func testSlowSecondDotTypesAfterTheAt() async throws {
        let (model, controller, textView, panel) = try await openTimestampedAlias(
            firstTimestamp: 1.0
        )
        defer { panel.orderOut(nil) }

        // 351 ms after the first key is past the window: an ordinary key.
        XCTAssertNotNil(typeKey(
            dotEvent(timestamp: 1.351),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil { textView.string == "Buy milk @." }
        XCTAssertNil(model.equalsGestureArm)
        XCTAssertEqual(model.plainDraft, "Buy milk @.")
    }

    func testTripleDotGivesDoubleDot() async throws {
        let (model, controller, textView, panel) = try await openTimestampedAlias(
            firstTimestamp: 1.0
        )
        defer { panel.orderOut(nil) }

        XCTAssertNil(controller.routeKeyDown(dotEvent(timestamp: 1.1)))
        XCTAssertEqual(textView.string, "Buy milk .")

        // The undo consumed the record, so the third `.` types natively.
        XCTAssertNotNil(typeKey(
            dotEvent(timestamp: 1.2),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil { textView.string == "Buy milk .." }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(textView.string, "Buy milk ..")
        XCTAssertFalse(model.completionVisible)
    }

    func testFastDoubleDotBeforeReplyCollapsesToOne() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Buy milk ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
        )

        XCTAssertNotNil(typeKey(
            dotEvent(timestamp: 1.0),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertEqual(textView.string, "Buy milk .")
        XCTAssertNotNil(typeKey(
            dotEvent(timestamp: 1.1),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertEqual(textView.string, "Buy milk ..")

        // The probe re-asks Bob about the first draft; the alias answer
        // collapses the pair without ever opening the route list.
        await waitUntil {
            textView.string == "Buy milk ." && model.equalsProbe == nil
        }
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.equalsGestureArm)
        let record = try String(contentsOf: recordURL)
        let asks = record.split(separator: "\n").filter {
            $0.hasPrefix("argv=capture-rewrite") && $0.hasSuffix("-- Buy milk .")
        }
        XCTAssertEqual(asks.count, 2)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Buy milk ..")
    }

    func testFastDoubleDotBeforeReplyLeavesPairWhenBobIsUnchanged() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Buy milk ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: [
                "FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4",
                "FAKE_BOB_REWRITE_DOT_ROUTE_UNCHANGED": "1",
            ]
        )

        XCTAssertNotNil(typeKey(
            dotEvent(timestamp: 1.0),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertNotNil(typeKey(
            dotEvent(timestamp: 1.1),
            into: textView,
            model: model,
            controller: controller
        ))
        XCTAssertEqual(textView.string, "Buy milk ..")

        await waitUntil { model.equalsProbe == nil }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(textView.string, "Buy milk ..")
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.equalsGestureArm)
    }

    func testOlderBobLeavesDotLiteralWithoutOpeningRouteList() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Buy milk ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DOT_ROUTE_UNCHANGED": "1"]
        )

        XCTAssertNotNil(typeKey(dotEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Buy milk ."
                && (try? String(contentsOf: recordURL))?.contains("argv=capture-rewrite") == true
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.equalsGestureArm)
    }

    func testDotToCaretReplyNeverArms() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "@file")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)

        XCTAssertNotNil(typeKey(dotEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "@file^" }
        XCTAssertNil(model.equalsGestureArm)
    }

    func testInterveningKeyClearsDotArm() async throws {
        let (model, controller, textView, panel) = try await openTimestampedAlias(
            firstTimestamp: 1.0
        )
        defer { panel.orderOut(nil) }

        // Any other key clears the `.` arm instead of surviving until
        // a later fast `.`.
        XCTAssertNotNil(typeKey(xEvent(), into: textView, model: model, controller: controller))
        XCTAssertNil(model.equalsGestureArm)
        XCTAssertNotNil(typeKey(
            dotEvent(timestamp: 1.1),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil { textView.string == "Buy milk @x." }
        XCTAssertNil(model.equalsGestureArm)
    }

    func testDownArrowClearsDotArm() async throws {
        let (model, controller, textView, panel) = try await openTimestampedAlias(
            firstTimestamp: 1.0
        )
        defer { panel.orderOut(nil) }

        _ = controller.routeKeyDown(downEvent())
        XCTAssertNil(model.equalsGestureArm)
        XCTAssertEqual(textView.string, "Buy milk @")
    }

    func testModifiedDotInvalidatesFastEscapeForCommandControlAndOption() async throws {
        let modifiersList: [NSEvent.ModifierFlags] = [.command, .control, .option]
        for modifiers in modifiersList {
            let (model, controller, textView, panel, _) = try await openAlias()
            defer { panel.orderOut(nil) }

            _ = controller.routeKeyDown(dotEvent(modifiers: modifiers, timestamp: 1.1))
            XCTAssertNil(model.equalsGestureArm)

            // With the arm invalidated, the next plain dot follows the normal
            // editor path instead of collapsing the alias to a literal dot.
            XCTAssertNotNil(controller.routeKeyDown(dotEvent(timestamp: 1.2)))
            XCTAssertEqual(textView.string, "Buy milk @")
            XCTAssertNil(model.equalsGestureArm)
        }
    }

    func testModifiedDotDisablesSpaceAndEscapeRestore() async throws {
        for restore in [spaceEvent(), escapeEvent()] {
            let (model, controller, textView, panel, _) = try await openAlias()
            defer { panel.orderOut(nil) }

            _ = controller.routeKeyDown(dotEvent(modifiers: .command, timestamp: 1.1))
            XCTAssertNil(model.equalsGestureArm)
            _ = controller.routeKeyDown(restore)

            XCTAssertEqual(textView.string, "Buy milk @")
            XCTAssertEqual(model.plainDraft, "Buy milk @")
            XCTAssertNil(model.equalsGestureArm)
        }
    }

    func testNavigationKeyInvalidatesPendingDotProbeBeforeFastSecondDot() async throws {
        let navigations = [
            ("Down", downEvent()),
            ("Up", upEvent()),
            ("Control-N", controlNEvent()),
            ("Control-P", controlPEvent()),
        ]

        for (name, navigation) in navigations {
            let recordURL = makeRecordURL()
            let (model, controller, textView, panel) = makeHostedEditor(text: "Buy milk ")
            defer { panel.orderOut(nil) }
            model.processClient = try processClient(
                recordURL: recordURL,
                extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
            )

            XCTAssertNotNil(typeKey(
                dotEvent(timestamp: 1.0),
                into: textView,
                model: model,
                controller: controller
            ))
            await waitUntil {
                (try? String(contentsOf: recordURL))?.contains("argv=capture-rewrite") == true
            } detail: {
                "; navigation=\(name)"
            }
            let beforeNavigation = textView.string
            let caretBeforeNavigation = textView.selectedRange()
            _ = controller.routeKeyDown(navigation)
            XCTAssertEqual(textView.string, beforeNavigation, "navigation=\(name)")
            XCTAssertEqual(textView.selectedRange(), caretBeforeNavigation, "navigation=\(name)")
            XCTAssertNil(model.pendingEqualsFirstKey, "navigation=\(name)")
            XCTAssertNil(model.equalsProbe, "navigation=\(name)")

            XCTAssertNotNil(typeKey(
                dotEvent(timestamp: 1.2),
                into: textView,
                model: model,
                controller: controller
            ), "navigation=\(name)")
            XCTAssertEqual(textView.string, "Buy milk ..", "navigation=\(name)")
            await waitUntil {
                (try? String(contentsOf: recordURL))?.contains("-- Buy milk ..") == true
                    && !model.rewriteInFlightForTesting
            } detail: {
                "; navigation=\(name), text=\(textView.string.debugDescription)"
            }
            XCTAssertEqual(textView.string, "Buy milk ..", "navigation=\(name)")
            XCTAssertNil(model.equalsGestureArm, "navigation=\(name)")
        }
    }

    func testNavigationBeforeReplyPreventsLateDotArmAndRestore() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Buy milk ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
        )

        XCTAssertNotNil(typeKey(
            dotEvent(timestamp: 1.0),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains("argv=capture-rewrite") == true
        }
        _ = controller.routeKeyDown(downEvent())
        XCTAssertEqual(textView.string, "Buy milk .")
        XCTAssertNil(model.pendingEqualsFirstKey)

        await waitUntil {
            textView.string == "Buy milk @" && !model.rewriteInFlightForTesting
        } detail: {
            aliasOpenDetail(textView: textView, model: model, recordURL: recordURL)
        }
        // Navigation while the rewrite is pending can dismiss the suggestion
        // list, but Bob's ordinary rewrite still applies without arming a
        // stale Escape/Space restore gesture.
        XCTAssertNil(model.equalsGestureArm)

        _ = controller.routeKeyDown(escapeEvent())
        XCTAssertEqual(textView.string, "Buy milk @")
        XCTAssertNil(model.equalsGestureArm)
    }

    func testCaretMoveClearsDotArm() async throws {
        let (model, controller, textView, panel) = try await openTimestampedAlias(
            firstTimestamp: 1.0
        )
        defer { panel.orderOut(nil) }

        textView.setSelectedRange(NSRange(location: 5, length: 0))
        model.editorSelectionDidChange(cursorUTF8Offset: 5)
        XCTAssertNil(model.equalsGestureArm)
    }

    func testDotGestureGuardsRepeatMarkedTextAndZeroTimestamps() {
        let model = CapturePanelModel()
        model.plainDraft = "Buy milk @"
        model.equalsGestureArm = CaptureEqualsGestureArm(
            surface: .editor,
            firstTimestamp: 1.0,
            isOpener: true,
            preDraft: "Buy milk ",
            preCaretUTF8: 9,
            postDraft: "Buy milk @",
            postCaretUTF8: 10,
            pickerSnapshot: nil,
            key: ".",
            sigil: "@"
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

    func testRouterFastDotUndoIsKeySpecific() {
        let router = CaptureKeyCommandRouter()
        var dotArmed = CaptureKeyRoutingContext()
        dotArmed.equalsGestureFastSecond = true
        dotArmed.equalsGestureFastSecondKey = "."
        XCTAssertEqual(
            router.command(for: dotEvent(), context: dotArmed),
            .undoEqualsGestureAndTypeLiteral
        )
        // `=` never takes the dot undo path.
        XCTAssertNil(router.command(for: equalsEvent(), context: dotArmed))

        var equalsArmed = CaptureKeyRoutingContext()
        equalsArmed.equalsGestureFastSecond = true
        equalsArmed.equalsGestureFastSecondKey = "="
        XCTAssertEqual(
            router.command(for: equalsEvent(), context: equalsArmed),
            .undoEqualsGestureAndTypeLiteral
        )
        // A `.` never takes the `=` undo path.
        XCTAssertNil(router.command(for: dotEvent(), context: equalsArmed))

        // Repeats fall through to the ordinary path.
        var repeating = dotArmed
        repeating.keyIsRepeat = true
        XCTAssertNil(router.command(for: dotEvent(), context: repeating))

        // Without a live record the key passes through natively.
        XCTAssertNil(router.command(
            for: dotEvent(),
            context: CaptureKeyRoutingContext()
        ))
    }

    func testDotProbeIgnoresEqualsPending() {
        let model = CapturePanelModel()
        model.plainDraft = "Fix it ="
        model.pendingEqualsFirstKey = (
            key: "=",
            draft: "Fix it =",
            caretUTF8: 7,
            timestamp: 1.0
        )
        XCTAssertFalse(model.equalsProbeReplyPending(
            liveString: "Fix it =",
            liveCaretUTF16: 7,
            hasMarkedText: false,
            typedKey: ".",
            timestamp: 1.1
        ))
        XCTAssertTrue(model.equalsProbeReplyPending(
            liveString: "Fix it =",
            liveCaretUTF16: 7,
            hasMarkedText: false,
            typedKey: "=",
            timestamp: 1.1
        ))
    }

    func testEqualsProbeIgnoresDotPending() {
        let model = CapturePanelModel()
        model.plainDraft = "Buy milk ."
        model.pendingEqualsFirstKey = (
            key: ".",
            draft: "Buy milk .",
            caretUTF8: 10,
            timestamp: 1.0
        )
        XCTAssertFalse(model.equalsProbeReplyPending(
            liveString: "Buy milk .",
            liveCaretUTF16: 10,
            hasMarkedText: false,
            typedKey: "=",
            timestamp: 1.1
        ))
        XCTAssertTrue(model.equalsProbeReplyPending(
            liveString: "Buy milk .",
            liveCaretUTF16: 10,
            hasMarkedText: false,
            typedKey: ".",
            timestamp: 1.1
        ))
    }
}
