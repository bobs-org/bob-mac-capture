import AppKit
import XCTest

@testable import BobMacCapture
@testable import CaptureCore

@MainActor
final class GcalNotePickerTests: XCTestCase {
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

    func testCommandEAndModeKeysPrecedeCaptureRoutes() {
        let router = CaptureKeyCommandRouter()
        let commandE = keyEvent(keyCode: 14, modifiers: .command, characters: "e")
        XCTAssertEqual(
            router.command(for: commandE, context: CaptureKeyRoutingContext(draftIsBlank: true)),
            .openGcalNote(nil)
        )
        XCTAssertEqual(
            router.command(
                for: commandE,
                context: CaptureKeyRoutingContext(
                    draftIsBlank: false,
                    calendarNoteActionIsFocused: true,
                    focusedCalendarNoteURL: "https://calendar.google.com/event?eid=private"
                )
            ),
            .openGcalNote("https://calendar.google.com/event?eid=private")
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 14, modifiers: .command, characters: "e", isRepeat: true)
            ),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(
                for: commandE,
                context: CaptureKeyRoutingContext(captureSubmitInFlight: true)
            ),
            .consumeKey
        )
        XCTAssertNil(
            router.command(
                for: commandE,
                context: CaptureKeyRoutingContext(editorHasMarkedText: true)
            )
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 14, modifiers: .control, characters: "e")),
            .moveToEndOfLineOrNextLine
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 38, modifiers: .command, characters: "j"),
                context: CaptureKeyRoutingContext(draftIsBlank: true)
            ),
            .joinCalendarEvent
        )

        let mode = CaptureKeyRoutingContext(gcalNoteModeVisible: true)
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 1, modifiers: [.control, .option], characters: "s"),
                context: mode
            ),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 53, characters: "\u{1b}"), context: mode),
            .gcalNoteEscape
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 126, characters: "\u{f700}"), context: mode),
            .gcalNoteMovePrevious
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, characters: "\r"), context: mode),
            .gcalNoteOpenSelected
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 14, modifiers: .control, characters: "e"),
                context: mode
            ),
            .gcalNotePassThrough
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 48, modifiers: .control, characters: "\t"),
                context: mode
            ),
            .switchPanel
        )
    }

    func testCalendarURLSurvivesAgendaPresentation() {
        let calendarURL = "https://calendar.google.com/event?eid=private"
        let source = CaptureAgendaEventRow(
            title: "Private meeting",
            calendarURL: calendarURL
        )
        let row = CaptureAgendaPresentation.makeCalendarEventRow(
            source,
            countdown: nil,
            startHint: nil
        )
        XCTAssertEqual(row.calendar?.eventNoteURL, calendarURL)
    }

    func testPickerFiltersLocallyMovesSelectionAndOpensOnlyOnSelection() async throws {
        let model = GcalNotePanelModel(processClient: client([
            "FAKE_BOB_GCAL_NOTE_LIST_FIXTURE": "gcal-note/list_all.json",
            "FAKE_BOB_GCAL_NOTE_SHOW_FIXTURE": "gcal-note/show.json",
        ]))
        model.present()
        await waitUntil { model.session?.phase == .listing }

        XCTAssertEqual(model.session?.events.count, 2)
        XCTAssertNil(model.session?.selectedIdentity)
        model.setFilter("Deerwood")
        XCTAssertEqual(model.pickerEvents.map(\.eventID), ["deerwood"])
        model.moveSelection(1)
        XCTAssertEqual(model.selectedPickerEvent?.eventID, "deerwood")
        XCTAssertNil(model.session?.selectedIdentity)

        model.openSelectedEvent()
        await waitUntil { model.session?.phase == .editing }
        XCTAssertEqual(model.session?.selectedEvent?.eventID, "deerwood")
        XCTAssertEqual(model.session?.selectedIdentity?.eventID, "deerwood")
    }

    func testFocusedCalendarURLResolvesAndAmbiguousURLRequiresSelection() async throws {
        let argvURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: argvURL) }
        let calendarURL = "https://calendar.google.com/event?eid=ambiguous"
        let urlModel = GcalNotePanelModel(processClient: client([
            "FAKE_BOB_GCAL_NOTE_SHOW_FIXTURE": "gcal-note/show.json",
            "FAKE_BOB_GCAL_NOTE_ARGV_PATH": argvURL.path,
        ]))
        urlModel.setCalendarNoteActionFocused(true, url: calendarURL)
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 14, modifiers: .command, characters: "e"),
                context: CaptureKeyRoutingContext(
                    calendarNoteActionIsFocused: urlModel.calendarNoteActionIsFocused,
                    focusedCalendarNoteURL: urlModel.focusedCalendarURL
                )
            ),
            .openGcalNote(calendarURL)
        )
        urlModel.present(url: urlModel.focusedCalendarURL)
        await waitUntil { urlModel.session?.phase == .editing }
        XCTAssertNotNil(urlModel.session?.selectedEvent)
        let argv = try String(contentsOf: argvURL, encoding: .utf8)
        XCTAssertTrue(argv.contains(calendarURL))

        let mapURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: mapURL) }
        let map: [String: String] = [
            "show": fixture("ambiguous.json"),
            "show:exact": fixture("show.json"),
        ]
        try JSONSerialization.data(withJSONObject: map).write(to: mapURL)
        let ambiguous = GcalNotePanelModel(processClient: client([
            "FAKE_BOB_GCAL_NOTE_FIXTURE_MAP": mapURL.path,
        ]))
        ambiguous.present(url: calendarURL)
        await waitUntil {
            ambiguous.session?.phase == .listing
                && ambiguous.session?.ambiguousCandidates.isEmpty == false
        }
        XCTAssertNil(ambiguous.session?.selectedIdentity)
        XCTAssertEqual(ambiguous.pickerEvents.count, 3)
        ambiguous.open(try XCTUnwrap(ambiguous.selectedPickerEvent))
        await waitUntil { ambiguous.session?.phase == .editing }
        XCTAssertEqual(ambiguous.session?.selectedEvent?.eventID, "deerwood")
    }

    func testUnsupportedBobHidesStatusMenuItemAndReplacementResetsCapability() async {
        let unsupported = GcalNotePanelModel(processClient: client([
            "FAKE_BOB_GCAL_NOTE_UNSUPPORTED": "1",
        ]))
        unsupported.present()
        await waitUntil { unsupported.session?.phase == .unsupported }
        XCTAssertTrue(unsupported.menuItemShouldBeHidden)

        let delegate = AppDelegate()
        delegate.eventNotePanelModel = unsupported
        let item = AppDelegate.makeStatusMenu().items[1]
        XCTAssertFalse(delegate.validateMenuItem(item))
        XCTAssertTrue(item.isHidden)

        unsupported.leave()
        unsupported.setProcessClient(client())
        XCTAssertFalse(unsupported.menuItemShouldBeHidden)
        XCTAssertTrue(delegate.validateMenuItem(item))
        XCTAssertFalse(item.isHidden)
    }

    func testCommandEOverlayRetainsCaptureEditorSelectionAndUndoManager() async throws {
        let capture = CapturePanelModel()
        capture.plainDraft = "Preserve this nonempty capture"
        let eventNotes = GcalNotePanelModel()
        let controller = CapturePanelController(model: capture, eventNotes: eventNotes)
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }
        controller.show()

        let editorCandidate = await waitForEditor(in: panel)
        let editor = try XCTUnwrap(editorCandidate)
        _ = panel.makeFirstResponder(editor)
        let selectedRange = NSRange(location: 8, length: 0)
        editor.setSelectedRange(selectedRange)
        let storage = try XCTUnwrap(editor.textStorage)
        let undoManager = try XCTUnwrap(editor.undoManager)
        let undoTarget = NSObject()
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: undoTarget) { _ in }
        undoManager.endUndoGrouping()
        undoManager.setActionName("Capture edit")
        XCTAssertTrue(undoManager.canUndo)

        XCTAssertNil(controller.routeKeyDown(
            keyEvent(
                keyCode: 14,
                modifiers: .command,
                characters: "e",
                windowNumber: panel.windowNumber
            )
        ))
        XCTAssertTrue(eventNotes.isPresented)
        XCTAssertTrue(findEditor(in: panel.contentView) === editor)
        XCTAssertTrue(editor.textStorage === storage)
        XCTAssertTrue(editor.undoManager === undoManager)
        XCTAssertEqual(editor.string, "Preserve this nonempty capture")
        XCTAssertEqual(editor.selectedRange(), selectedRange)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(capture.plainDraft, "Preserve this nonempty capture")

        let controlE = keyEvent(
            keyCode: 14,
            modifiers: .control,
            characters: "e",
            windowNumber: panel.windowNumber
        )
        XCTAssertNotNil(controller.routeKeyDown(controlE))
        XCTAssertEqual(capture.plainDraft, "Preserve this nonempty capture")

        XCTAssertNil(controller.routeKeyDown(
            keyEvent(keyCode: 53, characters: "\u{1b}", windowNumber: panel.windowNumber)
        ))
        await waitUntil { panel.firstResponder === editor }
        XCTAssertFalse(eventNotes.isPresented)
        XCTAssertTrue(findEditor(in: panel.contentView) === editor)
        XCTAssertTrue(editor.undoManager === undoManager)
        XCTAssertEqual(editor.selectedRange(), selectedRange)
    }

    func testPanelSwitchClosesModeAndReopeningRestoresDraft() async throws {
        let capture = CapturePanelModel()
        capture.plainDraft = "Draft survives a panel switch"
        let eventNotes = GcalNotePanelModel()
        let controller = CapturePanelController(model: capture, eventNotes: eventNotes)
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }
        controller.show()
        let editorCandidate = await waitForEditor(in: panel)
        let editor = try XCTUnwrap(editorCandidate)
        eventNotes.present()
        controller.panelSwitcher = { capture.closeRetainingDraft() }

        XCTAssertNil(controller.routeKeyDown(
            keyEvent(
                keyCode: 48,
                modifiers: .control,
                characters: "\t",
                windowNumber: panel.windowNumber
            )
        ))
        await waitUntil { !panel.isVisible }
        XCTAssertFalse(eventNotes.isPresented)
        XCTAssertEqual(capture.plainDraft, "Draft survives a panel switch")

        controller.show()
        XCTAssertTrue(findEditor(in: panel.contentView) === editor)
        XCTAssertEqual(editor.string, "Draft survives a panel switch")
    }

    private func waitForEditor(in panel: NSPanel, timeout: TimeInterval = 5) async -> NSTextView? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            panel.contentView?.layoutSubtreeIfNeeded()
            if let editor = findEditor(in: panel.contentView) {
                return editor
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return findEditor(in: panel.contentView)
    }

    private func findEditor(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView,
            textView.isEditable,
            textView.identifier?.rawValue != gcalNoteEditorAccessibilityIdentifier
        {
            return textView
        }
        for subview in view.subviews {
            if let found = findEditor(in: subview) {
                return found
            }
        }
        return nil
    }
}
