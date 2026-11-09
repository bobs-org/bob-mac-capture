import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureCloseAliasTests: XCTestCase {
    @MainActor
    private final class Editor {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        let controller: CapturePanelController
        let textView = NSTextView()
        let panel: NSPanel
        let directory: URL
        var recordURL: URL { directory.appendingPathComponent("calls") }
        var releaseURL: URL { directory.appendingPathComponent("release") }
        var pendingReplay: (@MainActor () -> Void)?

        init(_ text: String, extra: [String: String] = [:], supported: Bool = true) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            controller = CapturePanelController(model: model)
            panel = controller.makePanelIfNeeded()
            controller.typeAheadNow = { 0 }
            textView.isEditable = true
            textView.allowsUndo = true
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            model.plainDraft = text
            panel.contentView = textView
            XCTAssertTrue(panel.makeFirstResponder(textView))
            model.processClient = try client(extra: extra)
            if supported {
                model.installCloseAliasSupportForTests(supported: true)
            }
            controller.replayedKeyForTesting = { [weak self] event in
                guard let self else { return }
                self.textView.insertText(
                    event.characters ?? "", replacementRange: self.textView.selectedRange()
                )
                self.sync()
            }
        }

        func client(extra: [String: String] = [:]) throws -> BobProcessClient {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            var environment = [
                "HOME": "/tmp", "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_REWRITE_RELEASE_PATH": releaseURL.path,
            ]
            environment.merge(extra) { _, value in value }
            return BobProcessClient(
                executablePath: root.appendingPathComponent("Tests/Fixtures/fake-bob").path,
                environment: environment
            )
        }

        func sync() {
            // Mirror the editor binding. The programmatic plainDraft setter
            // clears the digit's pending comma-assist request before it can run.
            model.attributedDraft = AttributedString(textView.string)
            model.editorTextDidChange(
                cursorUTF8Offset: utf8Offset(
                    in: textView.string, utf16Offset: textView.selectedRange().location
                )
            )
        }

        @discardableResult
        func type(
            _ text: String, modifiers: NSEvent.ModifierFlags = [], timestamp: TimeInterval = 0
        ) -> NSEvent? {
            let keyCode: UInt16
            switch text {
            case "\r": keyCode = 36
            case "x": keyCode = 7
            case "s": keyCode = 1
            case "-": keyCode = 27
            case ".": keyCode = 47
            case "=": keyCode = 24
            case "z": keyCode = 6
            case "a": keyCode = 0
            case "2": keyCode = 19
            case "3": keyCode = 20
            default: keyCode = 18
            }
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: timestamp,
                windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: keyCode
            )!
            let routed = controller.routeKeyDown(event)
            if routed != nil {
                textView.insertText(text, replacementRange: textView.selectedRange())
                sync()
            } else if textView.string != model.plainDraft {
                sync()
            }
            return routed
        }

        func pauseReplay() {
            controller.scheduleTypeAheadReplay = { [weak self] dispatch in
                self?.pendingReplay = dispatch
            }
        }

        func stepReplay() {
            let dispatch = pendingReplay
            pendingReplay = nil
            dispatch?()
        }

        func focusOtherField() -> NSTextView {
            let other = NSTextView()
            other.isEditable = true
            other.string = ""
            textView.addSubview(other)
            XCTAssertTrue(panel.makeFirstResponder(other))
            return other
        }

        func interrupt(_ action: String) throws -> NSTextView? {
            switch action {
            case "caret":
                let arrow = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, characters: "",
                    charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123
                )!
                _ = controller.routeKeyDown(arrow)
                return nil
            case "focus":
                return focusOtherField()
            case "click":
                controller.noteMouseDownInPanel(windowNumber: panel.windowNumber)
                return nil
            case "resign":
                controller.windowDidResignKey(
                    Notification(name: NSWindow.didResignKeyNotification, object: panel)
                )
                return nil
            case "client":
                model.setProcessClient(try client())
                return nil
            case "direct-client":
                model.processClient = try client()
                return nil
            case "hide":
                model.panelDismisser()
                return nil
            default:
                _ = controller.windowShouldClose(panel)
                return nil
            }
        }

        func release() throws { try Data().write(to: releaseURL) }
        var record: String { (try? String(contentsOf: recordURL)) ?? "" }
        var writes: [Substring] {
            record.split(separator: "\n").filter {
                $0.hasPrefix("argv=capture --format json") && !$0.contains("--dry-run")
            }
        }
        func cleanup() {
            try? release()
            model.setProcessClient(nil)
            panel.orderOut(nil)
            // Keep paths until cancelled subprocesses have observed their release.
        }
    }

    private func waitUntil(
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(8)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            await Task.yield()
        }
    }

    func testBurstAliasesSubmitOnceAfterReplyIncludingCommandReturn() async throws {
        for (trigger, tail, expected) in [("x", "", "x!"), ("s", "1", "x*1")] {
            for modifiers in [NSEvent.ModifierFlags(), .command] {
                let editor = try Editor("x")
                defer { editor.cleanup() }
                XCTAssertNotNil(editor.type(trigger))
                for character in tail { XCTAssertNil(editor.type(String(character))) }
                XCTAssertNil(editor.type("\r", modifiers: modifiers))
                XCTAssertNil(editor.type("\r", modifiers: modifiers))
                XCTAssertEqual(editor.textView.string, "x" + trigger)
                XCTAssertTrue(editor.writes.isEmpty)
                try editor.release()
                await waitUntil { !editor.writes.isEmpty && !editor.model.isSubmitting }
                XCTAssertEqual(editor.textView.string, expected)
                XCTAssertEqual(editor.writes.count, 1, editor.record)
                XCTAssertTrue(
                    editor.writes.first?.hasSuffix("-- " + expected) == true, editor.record)
            }
        }
    }

    func testBurstPastAndChainedAliasesKeepOrderAndTimestamps() async throws {
        for (before, trigger, tail, expected) in [
            ("x=1=", "s", "3", "x=1=*3"), ("x1", "s", "2x3", "x1*2!3"),
        ] {
            let editor = try Editor(before)
            defer { editor.cleanup() }
            editor.type(trigger)
            for (index, character) in tail.enumerated() {
                XCTAssertNil(editor.type(String(character), timestamp: Double(index + 1)))
            }
            XCTAssertEqual(editor.textView.string, before + trigger)
            try editor.release()
            await waitUntil { editor.textView.string == expected }
            XCTAssertEqual(
                editor.controller.replayedKeyTimestampsForTesting,
                tail.enumerated().map { Double($0.offset + 1) })
            XCTAssertEqual(editor.controller.replayedKeyRouteCountForTesting, tail.count)
        }
    }

    func testHeldDigitsUseTheSameCommaAssistAsTypedWildcard() async throws {
        let editor = try Editor("x")
        defer { editor.cleanup() }
        editor.model.setCurrentPomodoroTaskLinkCountForTests(3)
        editor.type("s")
        XCTAssertNil(editor.type("1"))
        XCTAssertNil(editor.type("2"))
        try editor.release()
        await waitUntil { editor.textView.string == "x*1,2" }
        XCTAssertTrue(editor.record.contains("argv=capture-parse --format json -- x*1\n"))
        XCTAssertEqual(editor.controller.replayedKeyRouteCountForTesting, 2)
        // Bob's existing parse fixture, also used for a directly typed wildcard,
        // authorizes the comma only after the first digit.
        let client = try editor.client()
        let parse = try await client.captureParse("x*1")
        let direct = CaptureCloseTaskCommaAssist.edit(
            typed: "2", text: "x*1", selectedRange: NSRange(location: 3, length: 0),
            snapshot: CaptureParseSnapshot(draft: "x*1", parse: parse), taskLinkCount: 3
        )
        XCTAssertEqual(direct?.replacementText, ",2")
        XCTAssertEqual(editor.textView.string, "x*1" + (direct?.replacementText ?? ""))
    }

    func testNoChangeReplyReplaysAndSubmitsLiteral() async throws {
        let editor = try Editor("x", extra: ["FAKE_BOB_REWRITE_CLOSE_UNCHANGED": "1"])
        defer { editor.cleanup() }
        editor.type("s")
        editor.type("1")
        editor.type("\r")
        try editor.release()
        await waitUntil { !editor.writes.isEmpty && !editor.model.isSubmitting }
        XCTAssertEqual(editor.textView.string, "xs1")
        XCTAssertEqual(editor.writes.count, 1)
        XCTAssertTrue(editor.writes.first?.hasSuffix("-- xs1") == true, editor.record)
    }

    func testFailureAndDeadlineKeepLiteralAndDropReturn() async throws {
        for failure in [true, false] {
            let editor = try Editor("x", extra: failure ? ["FAKE_BOB_REWRITE_FAIL": "1"] : [:])
            defer { editor.cleanup() }
            var now: TimeInterval = 0
            editor.controller.typeAheadNow = { now }
            editor.type("s")
            editor.type("1")
            editor.type("\r")
            if failure {
                try editor.release()
            } else {
                now = 1
                editor.controller.expireTypeAheadHoldForTesting()
            }
            await waitUntil { editor.model.statusText == "Bob did not answer; press Return again" }
            XCTAssertEqual(editor.textView.string, "xs1")
            XCTAssertTrue(editor.writes.isEmpty, editor.record)
            XCTAssertFalse(editor.model.isSubmitting)
        }
    }

    func testCaretFocusClientReplacementAndDismissalFlushBeforeActing() throws {
        for action in ["caret", "focus", "client", "direct-client", "dismiss"] {
            let editor = try Editor("x")
            defer { editor.cleanup() }
            editor.type("s")
            editor.type("1")
            editor.type("\r")
            switch action {
            case "caret":
                let arrow = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: 123
                )!
                _ = editor.controller.routeKeyDown(arrow)
            case "focus": _ = editor.panel.makeFirstResponder(nil)
            case "client": editor.model.setProcessClient(try editor.client())
            case "direct-client": editor.model.processClient = try editor.client()
            default: _ = editor.controller.windowShouldClose(editor.panel)
            }
            XCTAssertEqual(editor.textView.string, "xs1", action)
            XCTAssertTrue(editor.writes.isEmpty, action)
            XCTAssertFalse(editor.model.isSubmitting, action)
        }
    }

    func testReplayInterruptionAfterReplyDrainsEditsAndDropsSubmit() async throws {
        let actions = [
            "caret", "focus", "click", "resign", "client", "direct-client", "dismiss",
            "hide",
        ]
        for submitModifiers in [NSEvent.ModifierFlags(), .command] {
            for action in actions {
                let editor = try Editor("x")
                defer { editor.cleanup() }
                editor.pauseReplay()
                editor.type("s")
                XCTAssertNil(editor.type("1"))
                XCTAssertNil(editor.type("\r", modifiers: submitModifiers))
                try editor.release()
                await waitUntil {
                    editor.pendingReplay != nil && editor.textView.string.hasPrefix("x*")
                }
                XCTAssertEqual(editor.textView.string, "x*", "\(action) \(submitModifiers)")
                let other = try editor.interrupt(action)
                XCTAssertEqual(editor.textView.string, "x*1", "\(action) \(submitModifiers)")
                XCTAssertTrue(editor.writes.isEmpty, "\(action) \(submitModifiers)")
                XCTAssertFalse(editor.model.isSubmitting, "\(action) \(submitModifiers)")
                if action == "dismiss" {
                    XCTAssertEqual(
                        editor.model.statusText, "Draft retained",
                        "\(action) \(submitModifiers)")
                } else {
                    XCTAssertEqual(
                        editor.model.statusText,
                        "Bob did not answer; press Return again",
                        "\(action) \(submitModifiers)")
                }
                XCTAssertEqual(other?.string ?? "", "", "\(action) \(submitModifiers)")
                editor.stepReplay()
                XCTAssertEqual(editor.textView.string, "x*1", "\(action) \(submitModifiers)")
                XCTAssertTrue(editor.writes.isEmpty, "\(action) \(submitModifiers)")
                XCTAssertFalse(editor.model.isSubmitting, "\(action) \(submitModifiers)")
                XCTAssertEqual(other?.string ?? "", "", "\(action) \(submitModifiers)")
                if action != "hide" {
                    _ = editor.panel.makeFirstResponder(editor.textView)
                    XCTAssertNotNil(editor.type("a"))
                    XCTAssertEqual(
                        editor.textView.string, "x*1a", "\(action) \(submitModifiers)")
                }
            }
        }
    }

    func testReplayInterruptionAfterOneDeliveredEditDropsRemainingSubmit() async throws {
        for action in ["caret", "focus", "client", "dismiss"] {
            let editor = try Editor("x")
            defer { editor.cleanup() }
            editor.pauseReplay()
            editor.type("s")
            XCTAssertNil(editor.type("1"))
            XCTAssertNil(editor.type("\r"))
            try editor.release()
            await waitUntil {
                editor.pendingReplay != nil && editor.textView.string.hasPrefix("x*")
            }
            editor.stepReplay()
            await waitUntil { editor.pendingReplay != nil }
            XCTAssertEqual(editor.textView.string, "x*1", action)
            let other = try editor.interrupt(action)
            XCTAssertEqual(editor.textView.string, "x*1", action)
            XCTAssertTrue(editor.writes.isEmpty, action)
            XCTAssertFalse(editor.model.isSubmitting, action)
            if action == "dismiss" {
                XCTAssertEqual(editor.model.statusText, "Draft retained", action)
            } else {
                XCTAssertEqual(
                    editor.model.statusText,
                    "Bob did not answer; press Return again",
                    action
                )
            }
            XCTAssertEqual(other?.string ?? "", "", action)
            editor.stepReplay()
            XCTAssertEqual(editor.textView.string, "x*1", action)
            XCTAssertTrue(editor.writes.isEmpty, action)
            XCTAssertFalse(editor.model.isSubmitting, action)
            XCTAssertEqual(other?.string ?? "", "", action)
        }
    }

    func testCommandFlushWhileReplaySuspendedDropsSubmit() async throws {
        let editor = try Editor("x")
        defer { editor.cleanup() }
        editor.pauseReplay()
        editor.type("s")
        XCTAssertNil(editor.type("1"))
        XCTAssertNil(editor.type("\r"))
        try editor.release()
        await waitUntil {
            editor.pendingReplay != nil && editor.textView.string.hasPrefix("x*")
        }
        let undo = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z",
            isARepeat: false, keyCode: 6
        )!
        _ = editor.controller.routeKeyDown(undo)
        XCTAssertEqual(editor.textView.string, "x*1")
        XCTAssertTrue(editor.writes.isEmpty)
        XCTAssertFalse(editor.model.isSubmitting)
        XCTAssertEqual(editor.model.statusText, "Bob did not answer; press Return again")
        editor.stepReplay()
        XCTAssertEqual(editor.textView.string, "x*1")
        XCTAssertTrue(editor.writes.isEmpty)
        XCTAssertFalse(editor.model.isSubmitting)
    }

    func testSameObjectRecheckDoesNotFlushReplayTail() async throws {
        let editor = try Editor("x")
        defer { editor.cleanup() }
        editor.pauseReplay()
        editor.type("s")
        XCTAssertNil(editor.type("1"))
        try editor.release()
        await waitUntil {
            editor.pendingReplay != nil && editor.textView.string.hasPrefix("x*")
        }
        editor.model.setProcessClient(editor.model.processClient)
        XCTAssertNotNil(editor.pendingReplay)
        XCTAssertEqual(editor.textView.string, "x*")
        editor.stepReplay()
        XCTAssertEqual(editor.textView.string, "x*1")
        XCTAssertTrue(editor.writes.isEmpty)
    }

    func testReplayedDotAndEqualsKeepSharedGestureOrder() async throws {
        let editor = try Editor("x")
        defer { editor.cleanup() }
        editor.type("s")
        XCTAssertNil(editor.type(".", timestamp: 1))
        XCTAssertNil(editor.type("=", timestamp: 2))
        try editor.release()
        await waitUntil { editor.textView.string == "x*.=" }
        XCTAssertEqual(editor.controller.replayedKeyTimestampsForTesting, [1, 2])
        XCTAssertEqual(editor.controller.replayedKeyRouteCountForTesting, 2)
    }

    func testOldBobProbeWarnsOnceAndReturnFilesLiteral() async throws {
        let editor = try Editor(
            "x", extra: ["FAKE_BOB_REWRITE_CLOSE_UNCHANGED": "1"], supported: false)
        defer { editor.cleanup() }
        try editor.release()
        await editor.model.awaitCloseAliasProbeForTests()
        XCTAssertFalse(editor.model.closeAliasForwardingAllowed())
        editor.type("x")
        XCTAssertEqual(editor.model.statusText, CapturePanelModel.closeAliasOldBobMessage)
        editor.model.statusText = ""
        editor.model.noteCloseAliasBlocked()
        XCTAssertEqual(editor.model.statusText, "")
        // Unsupported aliases use ordinary literal editing, with no rewrite
        // hold. Wait for its normal grammar/preview gate before pressing Return.
        await waitUntil {
            guard editor.model.captureGrammarAllowsSubmit else { return false }
            if case .ready = editor.model.previewState { return true }
            return false
        }
        editor.type("\r")
        await waitUntil { !editor.writes.isEmpty && !editor.model.isSubmitting }
        XCTAssertTrue(editor.writes.first?.hasSuffix("-- xx") == true, editor.record)
        XCTAssertEqual(editor.record.components(separatedBy: "argv=capture-rewrite").count - 1, 1)
    }

    func testProbeRunsForInitialClientAndCachesAcrossSameIdentity() async throws {
        let editor = try Editor("", supported: false)
        defer { editor.cleanup() }
        try editor.release()
        let client = try editor.client()
        let model = CapturePanelModel(processClient: client)
        await model.awaitCloseAliasProbeForTests()
        await editor.model.awaitCloseAliasProbeForTests()
        XCTAssertTrue(model.closeAliasForwardingAllowed())
        let before = editor.record.components(separatedBy: "argv=capture-rewrite").count
        model.setProcessClient(try editor.client())
        await model.awaitCloseAliasProbeForTests()
        XCTAssertTrue(model.closeAliasForwardingAllowed())
        XCTAssertEqual(editor.record.components(separatedBy: "argv=capture-rewrite").count, before)
    }

    func testClientReplacementDuringProbeRetriesEvenWithSameIdentity() async throws {
        let editor = try Editor("x", supported: false)
        defer { editor.cleanup() }
        await waitUntil { editor.record.contains("argv=capture-rewrite") }
        XCTAssertFalse(editor.model.closeAliasForwardingAllowed())
        editor.model.setProcessClient(try editor.client())
        try editor.release()
        await editor.model.awaitCloseAliasProbeForTests()
        XCTAssertTrue(editor.model.closeAliasForwardingAllowed())
    }

    func testPendingProbeLeavesTypedLettersLiteralAndDoesNotEditTheDraft() async throws {
        let editor = try Editor("x", supported: false)
        defer { editor.cleanup() }
        editor.type("x")
        XCTAssertEqual(editor.textView.string, "xx")
        XCTAssertFalse(editor.model.rewriteInFlightForTesting)
        XCTAssertFalse(editor.model.closeAliasAnnouncedForTests())
        try editor.release()
        await editor.model.awaitCloseAliasProbeForTests()
        XCTAssertTrue(editor.model.closeAliasForwardingAllowed())
        XCTAssertEqual(editor.textView.string, "xx")
    }

    func testProbeFailureRetriesOnRecheckWithSameClient() async throws {
        let editor = try Editor("x", supported: false)
        defer { editor.cleanup() }
        let failure = editor.directory.appendingPathComponent("failure")
        try Data().write(to: failure)
        let client = try editor.client(extra: ["FAKE_BOB_REWRITE_FAILURE_PATH": failure.path])
        editor.model.setProcessClient(client)
        try editor.release()
        await editor.model.awaitCloseAliasProbeForTests()
        XCTAssertFalse(editor.model.closeAliasForwardingAllowed())
        XCTAssertFalse(editor.model.closeAliasAnnouncedForTests())
        try FileManager.default.removeItem(at: failure)
        editor.model.setProcessClient(client)
        await editor.model.awaitCloseAliasProbeForTests()
        XCTAssertTrue(editor.model.closeAliasForwardingAllowed())
    }

    func testProbeAndEditorRewriteCannotCancelEachOther() async throws {
        let editor = try Editor("x=2", supported: false)
        defer { editor.cleanup() }
        await waitUntil { editor.record.contains("-- xx") }
        editor.type("-")
        try editor.release()
        await editor.model.awaitCloseAliasProbeForTests()
        await waitUntil { editor.textView.string == "x=2~" }
        XCTAssertTrue(editor.model.closeAliasForwardingAllowed())
    }
}
