import AppKit
import XCTest

@testable import BobMacCapture
@testable import CaptureCore

@MainActor
final class GcalNoteEditorTests: XCTestCase {
    private var testsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func client(_ environment: [String: String] = [:]) -> BobProcessClient {
        BobProcessClient(
            executablePath: testsRoot.appendingPathComponent("Fixtures/fake-bob").path,
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"].merging(environment) {
                _, new in new
            }
        )
    }

    private func fixture(_ name: String) -> String {
        testsRoot.appendingPathComponent("Fixtures/gcal-note/\(name)").path
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String,
        isRepeat: Bool = false,
        windowNumber: Int = 0
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
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

    func testEditorKeysSaveClearScopeAndNeverSubmitCapture() {
        let router = CaptureKeyCommandRouter()
        let editing = CaptureKeyRoutingContext(
            gcalNoteModeVisible: true,
            gcalNoteEditing: true
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, characters: "\r"), context: editing),
            .gcalNoteSave
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 76, characters: "\u{3}"), context: editing),
            .gcalNoteSave
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 36, modifiers: .shift, characters: "\r"),
                context: editing
            ),
            .gcalNotePassThrough
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 36, characters: "\r", isRepeat: true),
                context: editing
            ),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 51, modifiers: .command, characters: "\u{8}"),
                context: editing
            ),
            .gcalNoteClear
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 1, modifiers: [.control, .option], characters: "s"),
                context: editing
            ),
            .gcalNoteToggleScope
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 53, characters: "\u{1b}"), context: editing),
            .gcalNoteEscape
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 126, characters: "\u{f700}"), context: editing),
            .gcalNotePassThrough
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 45, modifiers: .control, characters: "n"),
                context: editing
            ),
            .gcalNotePassThrough
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 6, modifiers: .command, characters: "z"),
                context: editing
            ),
            .gcalNotePassThrough
        )
        let withUndo = CaptureKeyRoutingContext(
            gcalNoteModeVisible: true,
            gcalNoteEditing: true,
            gcalNoteCanUndoMutation: true
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 6, modifiers: .command, characters: "z"),
                context: withUndo
            ),
            .gcalNoteUndo
        )
        let picker = CaptureKeyRoutingContext(gcalNoteModeVisible: true)
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 6, modifiers: .command, characters: "z"),
                context: picker
            ),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, characters: "\r"), context: picker),
            .gcalNoteOpenSelected
        )
    }

    func testPickerEditorSaveUndoAndReturnRestoreCaptureUndo() async throws {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: store) }
        let capture = CapturePanelModel()
        capture.plainDraft = "Keep capture draft"
        let eventNotes = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_LIST_FIXTURE": "gcal-note/list_all.json",
                "FAKE_BOB_GCAL_NOTE_SHOW_FIXTURE": "gcal-note/show.json",
                "FAKE_BOB_GCAL_NOTE_STORE": store.path,
            ]))
        let controller = CapturePanelController(model: capture, eventNotes: eventNotes)
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }
        controller.show()
        let captureEditorCandidate = await waitForCaptureEditor(in: panel)
        let captureEditor = try XCTUnwrap(captureEditorCandidate)
        let captureUndo = try XCTUnwrap(captureEditor.undoManager)
        captureUndo.beginUndoGrouping()
        captureUndo.registerUndo(withTarget: NSObject()) { _ in }
        captureUndo.endUndoGrouping()
        XCTAssertTrue(captureUndo.canUndo)

        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(
                    keyCode: 14,
                    modifiers: .command,
                    characters: "e",
                    windowNumber: panel.windowNumber
                )
            ))
        await waitUntil { eventNotes.session?.phase == .listing }
        eventNotes.openSelectedEvent()
        await waitUntil { eventNotes.session?.phase == .editing }
        XCTAssertTrue(eventNotes.showsEditor)
        XCTAssertEqual(eventNotes.session?.editorText.contains("@family"), true)

        let noteEditorCandidate = await waitForNoteEditor(in: panel)
        let noteEditor = try XCTUnwrap(noteEditorCandidate)
        XCTAssertNotEqual(noteEditor, captureEditor)
        XCTAssertTrue(noteEditor.undoManager !== captureUndo)
        noteEditor.insertText(" extra", replacementRange: noteEditor.selectedRange())
        await waitUntil { eventNotes.session?.editorText.contains(" extra") == true }

        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(keyCode: 36, characters: "\r", windowNumber: panel.windowNumber)
            ))
        await waitUntil { eventNotes.session?.phase == .listing }
        XCTAssertEqual(capture.plainDraft, "Keep capture draft")
        XCTAssertTrue(eventNotes.session?.canUndoMutation == true)
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8).contains(" extra"), true)

        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(
                    keyCode: 6,
                    modifiers: .command,
                    characters: "z",
                    windowNumber: panel.windowNumber
                )
            ))
        await waitUntil { eventNotes.session?.canUndoMutation == false }
        XCTAssertTrue(captureUndo.canUndo)
        XCTAssertEqual(capture.plainDraft, "Keep capture draft")

        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(keyCode: 53, characters: "\u{1b}", windowNumber: panel.windowNumber)
            ))
        await waitUntil { !eventNotes.isPresented }
        XCTAssertEqual(capture.plainDraft, "Keep capture draft")
        XCTAssertTrue(captureUndo.canUndo)
    }

    func testClearRestoreAndFirstNoteAndInvalidUnicode() async throws {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: store) }
        let map = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: map) }
        try JSONSerialization.data(withJSONObject: [
            "list": fixture("list_all.json"),
            "show": fixture("show.json"),
            "preview": fixture("invalid.json"),
            "write": fixture("saved.json"),
            "clear": fixture("cleared.json"),
        ]).write(to: map)
        let eventNotes = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": map.path,
                "FAKE_BOB_GCAL_NOTE_STORE": store.path,
            ]))
        eventNotes.present()
        await waitUntil { eventNotes.session?.phase == .listing }
        eventNotes.openSelectedEvent()
        await waitUntil { eventNotes.session?.phase == .editing }

        let prior = try XCTUnwrap(eventNotes.session?.editorText)
        eventNotes.clear()
        await waitUntil { eventNotes.session?.phase == .listing }
        XCTAssertTrue(eventNotes.session?.canUndoMutation == true)
        eventNotes.undoLastMutation()
        await waitUntil { eventNotes.session?.canUndoMutation == false }
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), prior)

        eventNotes.openSelectedEvent()
        await waitUntil { eventNotes.session?.phase == .editing }
        eventNotes.session?.setEditorText("@famly")
        await waitUntil {
            eventNotes.session?.phase == .editing
                && eventNotes.session?.livePreview.isInvalid == true
                && eventNotes.session?.previewResponse?.input?.text == "@famly"
        }
        XCTAssertEqual(eventNotes.session?.livePreview.errors.first?.kind, "route_unknown")
        XCTAssertEqual(eventNotes.session?.phase, .editing)
    }

    func testRecurringScopeKeepsDraftsAndControlOptionSToggles() async throws {
        let map = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: map) }
        try JSONSerialization.data(withJSONObject: [
            "list": fixture("list_all.json"),
            "show:gym-1:event": fixture("both_scopes.json"),
            "show:gym-1:series": fixture("series_scope.json"),
            "show": fixture("both_scopes.json"),
        ]).write(to: map)
        let eventNotes = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": map.path
            ]))
        let controller = CapturePanelController(
            model: CapturePanelModel(),
            eventNotes: eventNotes
        )
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }
        eventNotes.present()
        await waitUntil { eventNotes.session?.phase == .listing }
        let recurring = try JSONDecoder().decode(
            GcalNoteShowResponse.self,
            from: Data(contentsOf: URL(fileURLWithPath: fixture("both_scopes.json")))
        )
        let event = try XCTUnwrap(recurring.event)
        eventNotes.session?.select(event)
        await waitUntil { eventNotes.session?.phase == .editing }
        eventNotes.session?.setEditorText("occurrence draft")
        await waitUntil { eventNotes.session?.editorText == "occurrence draft" }
        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(
                    keyCode: 1,
                    modifiers: [.control, .option],
                    characters: "s",
                    windowNumber: panel.windowNumber
                )
            ))
        await waitUntil {
            eventNotes.session?.scope == .series && eventNotes.session?.phase == .editing
        }
        XCTAssertEqual(eventNotes.session?.editorText, "")
        eventNotes.session?.setEditorText("series draft")
        await waitUntil { eventNotes.session?.editorText == "series draft" }
        eventNotes.toggleScope()
        await waitUntil { eventNotes.session?.scope == .event }
        XCTAssertEqual(eventNotes.session?.editorText, "occurrence draft")
    }

    func testEscapeFromEditorKeepsDraftThenLeavesToCapture() async throws {
        let eventNotes = GcalNotePanelModel(processClient: client())
        eventNotes.present()
        await waitUntil { eventNotes.session?.phase == .listing }
        eventNotes.openSelectedEvent()
        await waitUntil { eventNotes.session?.phase == .editing }
        eventNotes.session?.setEditorText("unsaved draft")
        await waitUntil { eventNotes.session?.editorText == "unsaved draft" }
        eventNotes.handleEscape()
        await waitUntil { eventNotes.session?.phase == .listing }
        XCTAssertTrue(eventNotes.isPresented)
        eventNotes.openSelectedEvent()
        await waitUntil { eventNotes.session?.phase == .editing }
        XCTAssertEqual(eventNotes.session?.editorText, "unsaved draft")
        eventNotes.handleEscape()
        await waitUntil { eventNotes.session?.phase == .listing }
        eventNotes.handleEscape()
        XCTAssertFalse(eventNotes.isPresented)
    }

    func testFirstNoteSaveAndUndoClearsTheNewNote() async throws {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: store) }
        let map = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: map) }
        try JSONSerialization.data(withJSONObject: [
            "list": fixture("list_all.json"),
            "show": fixture("series_scope.json"),
            "write": fixture("saved.json"),
            "clear": fixture("cleared.json"),
        ]).write(to: map)
        let eventNotes = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": map.path,
                "FAKE_BOB_GCAL_NOTE_STORE": store.path,
            ]))
        eventNotes.present()
        await waitUntil { eventNotes.session?.phase == .listing }
        eventNotes.openSelectedEvent()
        await waitUntil { eventNotes.session?.phase == .editing }
        XCTAssertEqual(eventNotes.session?.editorText, "")
        eventNotes.save()
        XCTAssertEqual(eventNotes.session?.phase, .editing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        eventNotes.session?.setEditorText("@family")
        await waitUntil { eventNotes.session?.isEditorDirty == true }
        eventNotes.save()
        await waitUntil { eventNotes.session?.phase == .listing }
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "@family")
        eventNotes.undoLastMutation()
        await waitUntil { eventNotes.session?.canUndoMutation == false }
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "")
    }

    func testClearSkipsInheritedSeriesWhenOccurrenceIsAbsent() async throws {
        let argvURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: argvURL) }
        let map = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        defer { try? FileManager.default.removeItem(at: map) }
        try JSONSerialization.data(withJSONObject: [
            "list": fixture("list_all.json"),
            "show": fixture("inherited_reasons.json"),
        ]).write(to: map)
        let eventNotes = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": map.path,
                "FAKE_BOB_GCAL_NOTE_ARGV_PATH": argvURL.path,
            ]))
        eventNotes.present()
        await waitUntil { eventNotes.session?.phase == .listing }
        eventNotes.openSelectedEvent()
        await waitUntil { eventNotes.session?.phase == .editing }
        XCTAssertEqual(eventNotes.session?.editorText, "")
        XCTAssertEqual(eventNotes.session?.canClearSavedScope, false)
        try? FileManager.default.removeItem(at: argvURL)
        eventNotes.clear()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(eventNotes.session?.phase, .editing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: argvURL.path))
    }

    func testNetworkFailureKeepsDraftAndShowsRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let errorFile = directory.appendingPathComponent("error")
        let eventNotes = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_ERROR_FILE": errorFile.path
            ]))
        eventNotes.present()
        await waitUntil { eventNotes.session?.phase == .listing }
        eventNotes.openSelectedEvent()
        await waitUntil { eventNotes.session?.phase == .editing }
        eventNotes.session?.setEditorText("@family\nKeep me")
        await waitUntil { eventNotes.session?.editorText == "@family\nKeep me" }
        try "network down".write(to: errorFile, atomically: true, encoding: .utf8)
        eventNotes.save()
        await waitUntil {
            if case .recoverableError(_, .reloadThenWrite, true) = eventNotes.session?.phase {
                return true
            }
            return false
        }
        XCTAssertEqual(eventNotes.session?.editorText, "@family\nKeep me")
        XCTAssertFalse(eventNotes.showsEditor)
    }

    func testUnsupportedOmitsOptionalEffectiveAndEmptyList() async throws {
        let unsupported = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_UNSUPPORTED": "1"
            ]))
        unsupported.present()
        await waitUntil { unsupported.session?.phase == .unsupported }
        XCTAssertFalse(unsupported.showsEditor)

        let empty = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_STDOUT": """
                {"ok":true,"schema_version":1,"events":[],"notes":[],"orphans":[],"warnings":[]}
                """
            ]))
        empty.present()
        await waitUntil { empty.session?.phase == .listing }
        XCTAssertTrue(empty.session?.isListEmpty == true)
        XCTAssertFalse(empty.showsEditor)

        let series = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_SHOW_FIXTURE": "gcal-note/series_scope.json"
            ]))
        series.present(url: "https://calendar.google.com/event?eid=gym-1")
        await waitUntil { series.session?.phase == .editing }
        XCTAssertNil(series.session?.showResponse?.effective?.buffer?.beforeReason)
        XCTAssertEqual(series.session?.livePreview.effective?.root?.hue, "violet")
    }

    func testNetworkAndSyncFailureAndRepeatReturn() async throws {
        let sync = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_WRITE_FIXTURE": "gcal-note/saved_sync_failed.json"
            ]))
        sync.present()
        await waitUntil { sync.session?.phase == .listing }
        sync.openSelectedEvent()
        await waitUntil { sync.session?.phase == .editing }
        sync.session?.setEditorText("@family")
        await waitUntil { sync.session?.isEditorDirty == true }
        sync.save()
        await waitUntil { sync.session?.phase == .listing }
        XCTAssertEqual(sync.session?.statusBanner?.state, "sync_failed")
        XCTAssertTrue(sync.session?.canUndoMutation == true)

        let delay = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_DELAY_SECONDS": "0.4"
            ]))
        let controller = CapturePanelController(
            model: CapturePanelModel(),
            eventNotes: delay
        )
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }
        delay.present()
        await waitUntil { delay.session?.phase == .listing }
        delay.openSelectedEvent()
        await waitUntil { delay.session?.phase == .editing }
        delay.session?.setEditorText("repeat")
        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(keyCode: 36, characters: "\r", windowNumber: panel.windowNumber)
            ))
        XCTAssertEqual(delay.session?.phase, .writing)
        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(keyCode: 36, characters: "\r", windowNumber: panel.windowNumber)
            ))
        await waitUntil { delay.session?.phase == .listing }
    }

    func testLongTextStaysInNoteEditor() async throws {
        let eventNotes = GcalNotePanelModel(processClient: client())
        let controller = CapturePanelController(
            model: CapturePanelModel(),
            eventNotes: eventNotes
        )
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }
        controller.show()
        eventNotes.present()
        await waitUntil { eventNotes.session?.phase == .listing }
        eventNotes.openSelectedEvent()
        await waitUntil { eventNotes.session?.phase == .editing }
        let long = String(repeating: "Unicode café 🎵 note line\n", count: 40)
        eventNotes.session?.setEditorText(long)
        let editorCandidate = await waitForNoteEditor(in: panel)
        let editor = try XCTUnwrap(editorCandidate)
        await waitUntil { editor.string.contains("Unicode café") }
        XCTAssertGreaterThan((editor.string as NSString).length, 200)
        XCTAssertEqual(
            editor.identifier?.rawValue,
            gcalNoteEditorAccessibilityIdentifier
        )
    }

    func testSavedNoteHighlightsWithoutTypingAndFitsSmallPanel() async throws {
        let eventNotes = GcalNotePanelModel(
            processClient: client([
                "FAKE_BOB_GCAL_NOTE_SHOW_FIXTURE": "gcal-note/show_preview_match.json",
                "FAKE_BOB_GCAL_NOTE_PREVIEW_FIXTURE": "gcal-note/preview_match.json",
            ]))
        let controller = CapturePanelController(
            model: CapturePanelModel(),
            eventNotes: eventNotes
        )
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }
        controller.show()
        eventNotes.present()
        await waitUntil { eventNotes.session?.phase == .listing }
        panel.setContentSize(NSSize(width: 480, height: 520))
        eventNotes.openSelectedEvent()
        await waitUntil {
            eventNotes.session?.phase == .editing
                && eventNotes.session?.isEditorDirty == false
                && eventNotes.session?.previewResponse?.input?.text
                    == eventNotes.session?.editorText
        }

        let editorCandidate = await waitForNoteEditor(in: panel)
        let editor = try XCTUnwrap(editorCandidate)
        XCTAssertEqual(editor.string, eventNotes.session?.editorText)
        XCTAssertFalse(eventNotes.session?.isEditorDirty ?? true)
        await waitUntil {
            guard let storage = editor.textStorage, storage.length > 0 else {
                return false
            }
            let color =
                storage.attribute(
                    .foregroundColor,
                    at: 0,
                    effectiveRange: nil
                ) as? NSColor
            return color?.isEqual(NSColor.labelColor) == false
        }
        let highlight =
            editor.textStorage?.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        XCTAssertNotNil(highlight)
        XCTAssertFalse(highlight?.isEqual(NSColor.labelColor) ?? true)

        panel.setContentSize(NSSize(width: 480, height: 520))
        guard let content = panel.contentView else {
            XCTFail("The small capture panel has no content view")
            return
        }
        content.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(editor.visibleRect.height, 1)
        let visibleEditorFrame = editor.convert(editor.visibleRect, to: content)
        XCTAssertTrue(content.bounds.contains(visibleEditorFrame))
        XCTAssertLessThan(visibleEditorFrame.height, content.bounds.height - 100)
    }

    private func waitForNoteEditor(
        in panel: NSPanel,
        timeout: TimeInterval = 5
    ) async -> NSTextView? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            panel.contentView?.layoutSubtreeIfNeeded()
            if let editor = findNoteEditor(in: panel.contentView) {
                return editor
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return findNoteEditor(in: panel.contentView)
    }

    private func waitForCaptureEditor(
        in panel: NSPanel,
        timeout: TimeInterval = 5
    ) async -> NSTextView? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            panel.contentView?.layoutSubtreeIfNeeded()
            if let editor = findCaptureEditor(in: panel.contentView) {
                return editor
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return findCaptureEditor(in: panel.contentView)
    }

    private func findNoteEditor(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView,
            textView.identifier?.rawValue == gcalNoteEditorAccessibilityIdentifier
        {
            return textView
        }
        for subview in view.subviews {
            if let found = findNoteEditor(in: subview) {
                return found
            }
        }
        return nil
    }

    private func findCaptureEditor(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView,
            textView.isEditable,
            textView.identifier?.rawValue != gcalNoteEditorAccessibilityIdentifier
        {
            return textView
        }
        for subview in view.subviews {
            if let found = findCaptureEditor(in: subview) {
                return found
            }
        }
        return nil
    }

}
