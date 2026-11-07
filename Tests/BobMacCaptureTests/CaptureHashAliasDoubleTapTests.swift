import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Slow and fast `\` `\` double-tap after a `#` alias, driven through the
/// real `routeKeyDown` with a hosted panel and the live editor as the
/// first responder.
@MainActor
final class CaptureHashAliasDoubleTapTests: XCTestCase {
    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String,
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
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(
            keyCode: 42,
            modifiers: modifiers,
            characters: "\\",
            isRepeat: isRepeat
        )
    }

    private func slashEvent(
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(
            keyCode: 44,
            modifiers: modifiers,
            characters: "/",
            isRepeat: isRepeat
        )
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
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        // Mirror the initial text into the model, as the SwiftUI binding
        // would: without it the model sees a blank draft and the first key
        // routes to Go To instead of the rewrite lane.
        model.plainDraft = text
        panel.contentView = textView
        XCTAssertTrue(panel.makeFirstResponder(textView))
        return (model, controller, textView, panel)
    }

    /// Types one key through `routeKeyDown`, inserting natively when AppKit
    /// keeps the event, then syncing the mirror the way the SwiftUI binding
    /// would. Returns the router result (`nil` means consumed).
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
        textView.insertText(
            event.characters ?? "",
            replacementRange: textView.selectedRange()
        )
        model.plainDraft = textView.string
        let caretUTF16 = textView.selectedRange().location
        let caretUTF8 = utf8Offset(in: textView.string, utf16Offset: caretUTF16)
            ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
        return result
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

    /// State dump for an alias that never opened its menu, so a rare CI
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
            + " completion=\(String(describing: model.completionResponse?.context))"
            + " completionVisible=\(model.completionVisible)"
            + " rewriteInFlight=\(model.rewriteInFlightForTesting)"
            + " argv=\(argv)"
    }

    private func makeRecordURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    // MARK: - Slow double-tap

    func testSlowDoubleTapClosesMenuWithOneLiteralBackslash() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "jot idea #" && model.completionVisible
        } detail: {
            aliasOpenDetail(textView: textView, model: model, recordURL: recordURL)
        }
        // A current bob opens the task_type menu here; this environment
        // answers route (the pre-existing task-type test sees the same).
        // Assert only that a menu opened.
        XCTAssertNotNil(model.completionResponse)
        XCTAssertFalse(model.completionResponse?.candidates.isEmpty ?? true)

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 10 --format json -- jot idea \\"))
        let completesBefore = record.components(separatedBy: "argv=capture-complete").count - 1

        XCTAssertNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "jot idea \\")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0))
        XCTAssertFalse(model.completionVisible)

        try await Task.sleep(nanoseconds: 200_000_000)
        let after = try String(contentsOf: recordURL)
        XCTAssertEqual(after.components(separatedBy: "argv=capture-complete").count - 1, completesBefore)
        XCTAssertFalse(after.contains("capture-complete --all-tasks --cursor 10 --format json -- jot idea \\"))
    }

    func testDrawerDoubleTapClosesMenuWithOneLiteralBackslash() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(
            text: "Postgres 17 minimum @foo+bar"
        )
        defer { panel.orderOut(nil) }
        model.processClient = try processClient()

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "Postgres 17 minimum @foo+bar#" && model.completionVisible }
        XCTAssertEqual(model.completionResponse?.context, "drawer")

        XCTAssertNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Postgres 17 minimum @foo+bar\\")
        XCTAssertFalse(model.completionVisible)
    }

    func testMirrorLagStillConsumesSecondBackslash() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient()

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "jot idea #" && model.completionVisible }

        // The SwiftUI mirror lags the editor: the old code judged the arm
        // against this stale selection and lost the double-tap.
        model.editorSelection = AttributedTextSelection(
            insertionPoint: model.attributedDraft.startIndex
        )
        XCTAssertNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "jot idea \\")
        XCTAssertFalse(model.completionVisible)
    }

    func testStaleCaretPassesThroughAndDropsArm() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient()

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "jot idea #" && model.completionVisible }

        textView.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "jot i\\dea #")
        XCTAssertNil(model.hashAliasLiteralArm)
    }

    func testRepeatWhileArmedIsConsumedAndArmStays() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient()

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "jot idea #" && model.completionVisible }

        XCTAssertNil(
            typeKey(
                backslashEvent(isRepeat: true),
                into: textView,
                model: model,
                controller: controller
            )
        )
        XCTAssertEqual(textView.string, "jot idea #")
        XCTAssertNotNil(model.hashAliasLiteralArm)

        XCTAssertNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "jot idea \\")
        XCTAssertFalse(model.completionVisible)
    }

    func testUndoAfterDoubleTapRestoresHashThenBackslash() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient()

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "jot idea #" && model.completionVisible }
        XCTAssertNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "jot idea \\")

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "jot idea #")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "jot idea \\")
    }

    // MARK: - Fast double-tap (collapse)

    func testFastDoubleTapCollapsesToOneLiteralBackslash() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.3"]
        )

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "jot idea \\\\")

        let deadline = Date().addingTimeInterval(5)
        var sawHash = false
        while Date() < deadline {
            if textView.string.contains("#") {
                sawHash = true
                break
            }
            if textView.string == "jot idea \\" && model.hashAliasProbe == nil {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(sawHash, "The alias # must never appear during a fast double-tap")
        XCTAssertEqual(textView.string, "jot idea \\")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0))
        XCTAssertFalse(model.completionVisible)

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 10 --format json -- jot idea \\"))
        let rewriteLines = record
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("argv=capture-rewrite") }
        XCTAssertTrue(rewriteLines.allSatisfy { !$0.hasSuffix("jot idea \\\\") })

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "jot idea \\\\")
    }

    func testFastDoubleTapWithoutAliasKeepsTwoBackslashes() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            extra: ["FAKE_BOB_REWRITE_HASH_UNCHANGED": "1"]
        )

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { model.plainDraft == "jot idea \\\\" }
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(textView.string, "jot idea \\\\")
        XCTAssertEqual(model.plainDraft, "jot idea \\\\")
        XCTAssertNil(model.hashAliasLiteralArm)
        XCTAssertNil(model.hashAliasProbe)
    }

    func testThirdKeyBeforeReplyLeavesDoubleBackslashPlusKey() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.3"]
        )

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNotNil(
            typeKey(
                keyEvent(keyCode: 7, characters: "x"),
                into: textView,
                model: model,
                controller: controller
            )
        )
        await waitUntil { model.plainDraft == "jot idea \\\\x" }
        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(textView.string, "jot idea \\\\x")
        XCTAssertFalse(textView.string.contains("#"))
        XCTAssertNil(model.hashAliasProbe)
        XCTAssertNil(model.hashAliasLiteralArm)
    }

    // MARK: - Slow slash double-tap

    func testSlowSlashDoubleTapClosesMenuWithOneLiteralSlash() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(
            text: "Postgres 17 minimum @foo+bar"
        )
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)

        XCTAssertNotNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Postgres 17 minimum @foo+bar#" && model.completionVisible
        } detail: {
            aliasOpenDetail(textView: textView, model: model, recordURL: recordURL)
        }
        XCTAssertEqual(model.completionResponse?.context, "drawer")
        XCTAssertEqual(model.hashAliasLiteralArm?.key, "/")

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 29 --format json -- Postgres 17 minimum @foo+bar/"))
        let completesBefore = record.components(separatedBy: "argv=capture-complete").count - 1

        XCTAssertNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Postgres 17 minimum @foo+bar/")
        XCTAssertFalse(model.completionVisible)

        try await Task.sleep(nanoseconds: 200_000_000)
        let after = try String(contentsOf: recordURL)
        XCTAssertEqual(after.components(separatedBy: "argv=capture-complete").count - 1, completesBefore)
        XCTAssertFalse(after.contains("capture-complete --cursor 29 --format json -- Postgres 17 minimum @foo+bar/"))
    }

    func testSlashRepeatWhileArmedIsConsumedAndArmStays() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient()

        XCTAssertNotNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "jot idea #" && model.completionVisible }

        XCTAssertNil(
            typeKey(
                slashEvent(isRepeat: true),
                into: textView,
                model: model,
                controller: controller
            )
        )
        XCTAssertEqual(textView.string, "jot idea #")
        XCTAssertEqual(model.hashAliasLiteralArm?.key, "/")

        XCTAssertNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "jot idea /")
        XCTAssertFalse(model.completionVisible)
    }

    func testMixedKeysBackslashThenSlashEndsHashSlash() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient()

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "jot idea #" && model.completionVisible }
        XCTAssertEqual(model.hashAliasLiteralArm?.key, "\\")

        XCTAssertNotNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { model.plainDraft == "jot idea #/" }
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(textView.string, "jot idea #/")
        XCTAssertNil(model.hashAliasLiteralArm)
        XCTAssertNil(model.hashAliasProbe)
    }

    func testMixedKeysSlashThenBackslashEndsHashBackslash() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient()

        XCTAssertNotNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "jot idea #" && model.completionVisible }
        XCTAssertEqual(model.hashAliasLiteralArm?.key, "/")

        XCTAssertNotNil(typeKey(backslashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { model.plainDraft == "jot idea #\\" }
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(textView.string, "jot idea #\\")
        XCTAssertNil(model.hashAliasLiteralArm)
        XCTAssertNil(model.hashAliasProbe)
    }

    // MARK: - Fast slash double-tap (collapse)

    func testFastSlashDoubleTapCollapsesToOneLiteralSlash() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.3"]
        )

        XCTAssertNotNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNotNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "jot idea //")

        let deadline = Date().addingTimeInterval(5)
        var sawHash = false
        while Date() < deadline {
            if textView.string.contains("#") {
                sawHash = true
                break
            }
            if textView.string == "jot idea /" && model.hashAliasProbe == nil {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(sawHash, "The alias # must never appear during a fast double-tap")
        XCTAssertEqual(textView.string, "jot idea /")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0))
        XCTAssertFalse(model.completionVisible)

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 10 --format json -- jot idea /"))
        let rewriteLines = record
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("argv=capture-rewrite") }
        XCTAssertTrue(rewriteLines.allSatisfy { !$0.hasSuffix("jot idea //") })

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "jot idea //")
    }

    func testFastSlashDoubleTapWithoutAliasKeepsTwoSlashes() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(text: "jot idea ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            extra: ["FAKE_BOB_REWRITE_HASH_UNCHANGED": "1"]
        )

        XCTAssertNotNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNotNil(typeKey(slashEvent(), into: textView, model: model, controller: controller))
        await waitUntil { model.plainDraft == "jot idea //" }
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(textView.string, "jot idea //")
        XCTAssertEqual(model.plainDraft, "jot idea //")
        XCTAssertNil(model.hashAliasLiteralArm)
        XCTAssertNil(model.hashAliasProbe)
    }
}
