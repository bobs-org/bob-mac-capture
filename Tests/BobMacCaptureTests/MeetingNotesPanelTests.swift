import AppKit
import XCTest

@testable import BobMacCapture
@testable import CaptureCore

@MainActor
final class MeetingNotesPanelTests: XCTestCase {
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

    func testChooserUsesDistinctRowIdentityAndSkipsTokenlessRows() async {
        let model = MeetingNotesPanelModel(
            processClient: client([
                "FAKE_BOB_MEETING_NOTES_LIST_FIXTURE": "meeting-notes/list-same-path.json",
            ])
        )
        model.present()
        await waitUntil {
            model.session?.state == .previewReady && model.session?.meetings.count == 3
        }
        model.showChooser()
        await waitUntil {
            model.session?.state == .choosingMeeting && model.pickerRows.count == 3
        }
        let ids = model.pickerRows.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(model.selectablePickerMeetings.allSatisfy(\.canSelect))
        XCTAssertFalse(model.pickerMeetings.allSatisfy(\.canSelect))
        XCTAssertNotNil(model.selectedMeetingRef)
        XCTAssertNotEqual(model.selectedMeetingRef, "")
        model.filterText = "Untitled"
        XCTAssertTrue(model.selectablePickerMeetings.isEmpty)
        XCTAssertNil(model.selectedMeetingRef)
        model.filterText = "Orchard"
        XCTAssertEqual(model.selectablePickerMeetings.count, 1)
        XCTAssertEqual(model.selectedMeetingRef, "20261124#^orchard")
    }

    func testChangeMeetingOpensChooserAndEscapeRestoresPreview() async {
        let model = MeetingNotesPanelModel(processClient: client())
        model.present()
        await waitUntil { model.session?.state == .previewReady }
        XCTAssertEqual(model.keySurface, .preview)
        model.showChooser()
        await waitUntil { model.session?.state == .choosingMeeting }
        XCTAssertEqual(model.keySurface, .choosingMeeting)
        model.handleEscape()
        XCTAssertEqual(model.session?.state, .previewReady)
        XCTAssertTrue(model.isPresented)
        XCTAssertTrue(model.session?.canFile == true)
    }

    func testParentAndReplaceKeyboardActivateWithoutFiling() async {
        let model = MeetingNotesPanelModel(
            processClient: client([
                "FAKE_BOB_MEETING_NOTES_PREVIEW_FIXTURE": "meeting-notes/needs-parent.json"
            ])
        )
        var opened: [String] = []
        model.onOpenNote = { opened.append($0) }
        model.present(eventRef: "20261124#^spruce-sync")
        await waitUntil { model.session?.state == .choosingParent }
        XCTAssertEqual(model.selectedParentRoute, "team")
        model.moveSelection(1)
        XCTAssertEqual(model.selectedParentRoute, "studio")
        model.openSelectedMeeting()
        await waitUntil { model.session?.parent == "studio" }

        let replace = MeetingNotesPanelModel(
            processClient: client([
                "FAKE_BOB_MEETING_NOTES_PREVIEW_FIXTURE": "meeting-notes/already-filed.json"
            ])
        )
        replace.onOpenNote = { opened.append($0) }
        replace.present(eventRef: "20261124#^spruce-sync")
        await waitUntil { replace.session?.state == .confirmingReplace }
        XCTAssertTrue(replace.replaceActions.contains(.openExisting))
        replace.moveSelection(-1)
        XCTAssertEqual(replace.selectedReplaceAction, .openExisting)
        replace.openSelectedMeeting()
        XCTAssertEqual(opened.last, "ref/meetings/261124_juniper_systems_planning.md")
        XCTAssertEqual(replace.session?.state, .confirmingReplace)
        XCTAssertFalse(replace.session?.canFile == true)
    }

    func testLeaveDuringWriteKeepsSheetAndReceipt() async {
        let model = MeetingNotesPanelModel(
            processClient: client([
                "FAKE_BOB_MEETING_NOTES_WRITE_DELAY_SECONDS": "0.4"
            ])
        )
        var receipts: [MeetingNotesOutcome] = []
        model.onReceipt = { receipt in
            if let outcome = receipt.outcome {
                receipts.append(outcome)
            }
        }
        model.present()
        await waitUntil { model.session?.state == .previewReady }
        model.file()
        await waitUntil { model.isWriting }
        XCTAssertTrue(model.isPresented)
        model.leave()
        XCTAssertTrue(model.isPresented)
        XCTAssertTrue(model.isWriting)
        let replacement = client()
        model.setProcessClient(replacement)
        XCTAssertTrue(model.isWriting)
        await waitUntil { model.session?.state == .filed }
        XCTAssertTrue(model.isPresented)
        XCTAssertEqual(model.session?.state, .filed)
        XCTAssertEqual(receipts, [.filed])
        model.leave()
        XCTAssertFalse(model.isPresented)
    }

    func testEntryGatesAndKnownUnsupportedHideActions() async {
        let capture = CapturePanelModel()
        capture.isSubmitting = true
        let meetingNotes = MeetingNotesPanelModel(processClient: client())
        let controller = CapturePanelController(model: capture, meetingNotes: meetingNotes)
        controller.showMeetingNotes()
        XCTAssertFalse(meetingNotes.isPresented)

        capture.isSubmitting = false
        let unsupported = MeetingNotesPanelModel(
            processClient: client(["FAKE_BOB_MEETING_NOTES_UNSUPPORTED": "1"])
        )
        unsupported.present()
        await waitUntil { unsupported.session?.state == .unsupported }
        XCTAssertTrue(unsupported.entryShouldBeHidden)
        XCTAssertTrue(unsupported.menuItemShouldBeHidden)
        unsupported.present()
        XCTAssertEqual(unsupported.session?.state, .unsupported)
    }

    func testCommandMOverlayRetainsCaptureDraftAndConsumesPassThrough() async throws {
        let capture = CapturePanelModel()
        capture.plainDraft = "Preserve this nonempty capture"
        let meetingNotes = MeetingNotesPanelModel(processClient: client())
        let controller = CapturePanelController(model: capture, meetingNotes: meetingNotes)
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }
        controller.show()

        let editorCandidate = await waitForEditor(in: panel)
        let editor = try XCTUnwrap(editorCandidate)
        _ = panel.makeFirstResponder(editor)
        let selectedRange = NSRange(location: 8, length: 0)
        editor.setSelectedRange(selectedRange)

        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(
                    keyCode: 46,
                    modifiers: .command,
                    characters: "m",
                    windowNumber: panel.windowNumber
                )
            )
        )
        XCTAssertTrue(meetingNotes.isPresented)
        XCTAssertEqual(capture.plainDraft, "Preserve this nonempty capture")
        XCTAssertEqual(editor.string, "Preserve this nonempty capture")

        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(
                    keyCode: 0,
                    characters: "a",
                    windowNumber: panel.windowNumber
                )
            )
        )
        XCTAssertEqual(capture.plainDraft, "Preserve this nonempty capture")
        XCTAssertEqual(editor.string, "Preserve this nonempty capture")

        XCTAssertNil(
            controller.routeKeyDown(
                keyEvent(keyCode: 53, characters: "\u{1b}", windowNumber: panel.windowNumber)
            )
        )
        await waitUntil { !meetingNotes.isPresented }
        XCTAssertEqual(capture.plainDraft, "Preserve this nonempty capture")
    }

    func testHideAndEventNoteLeaveWritingSheetAlone() async {
        let capture = CapturePanelModel()
        let meetingNotes = MeetingNotesPanelModel(
            processClient: client([
                "FAKE_BOB_MEETING_NOTES_WRITE_DELAY_SECONDS": "0.4"
            ])
        )
        let eventNotes = GcalNotePanelModel()
        let controller = CapturePanelController(
            model: capture, eventNotes: eventNotes, meetingNotes: meetingNotes)
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }
        controller.show()
        meetingNotes.present()
        await waitUntil { meetingNotes.session?.state == .previewReady }
        meetingNotes.file()
        await waitUntil { meetingNotes.isWriting }
        capture.closeRetainingDraft()
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(meetingNotes.isPresented)
        controller.showEventNotes()
        XCTAssertFalse(eventNotes.isPresented)
        XCTAssertTrue(meetingNotes.isWriting)
        await waitUntil { meetingNotes.session?.state == .filed }
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
        if let textView = view as? NSTextView, textView.isEditable, !textView.isFieldEditor {
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
