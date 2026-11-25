import AppKit
import XCTest

@testable import BobMacCapture
@testable import CaptureCore

@MainActor
final class MeetingNotesKeyRouterTests: XCTestCase {
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
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }

    func testCommandMOpensMeetingNotesWithFocusedRef() {
        let router = CaptureKeyCommandRouter()
        let commandM = keyEvent(keyCode: 46, modifiers: .command, characters: "m")
        XCTAssertEqual(
            router.command(for: commandM, context: CaptureKeyRoutingContext()),
            .openMeetingNotes(nil)
        )
        XCTAssertEqual(
            router.command(
                for: commandM,
                context: CaptureKeyRoutingContext(
                    meetingNotesActionIsFocused: true,
                    focusedMeetingRef: "20261123#^standup"
                )
            ),
            .openMeetingNotes("20261123#^standup")
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 46, modifiers: .command, characters: "m", isRepeat: true)),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(
                for: commandM,
                context: CaptureKeyRoutingContext(captureSubmitInFlight: true)),
            .consumeKey
        )
        XCTAssertNil(
            router.command(
                for: commandM,
                context: CaptureKeyRoutingContext(editorHasMarkedText: true))
        )
    }

    func testMeetingNotesModeEscapeAliases() {
        let router = CaptureKeyCommandRouter()
        let base = CaptureKeyRoutingContext(meetingNotesModeVisible: true)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 53, characters: ""), context: base),
            .meetingNotesEscape
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 33, modifiers: .control, characters: "["),
                context: base),
            .meetingNotesEscape
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 12, characters: "q"), context: base),
            .meetingNotesEscape
        )
        // q stays typeable when the filter holds focus.
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 12, characters: "q"),
                context: CaptureKeyRoutingContext(
                    meetingNotesModeVisible: true, meetingNotesFilterFocused: true)),
            .meetingNotesPassThrough
        )
        // IME composition never escapes.
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 53, characters: ""),
                context: CaptureKeyRoutingContext(
                    meetingNotesModeVisible: true, editorHasMarkedText: true)),
            .meetingNotesPassThrough
        )
    }

    func testMeetingNotesModeReturnFilesOrSelects() {
        let router = CaptureKeyCommandRouter()
        let ret = keyEvent(keyCode: 36, characters: "\r")
        XCTAssertEqual(
            router.command(
                for: ret,
                context: CaptureKeyRoutingContext(
                    meetingNotesModeVisible: true, meetingNotesCanFile: true)),
            .meetingNotesFile
        )
        XCTAssertEqual(
            router.command(
                for: ret,
                context: CaptureKeyRoutingContext(meetingNotesModeVisible: true)),
            .meetingNotesOpenSelected
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 36, characters: "\r", isRepeat: true),
                context: CaptureKeyRoutingContext(
                    meetingNotesModeVisible: true, meetingNotesCanFile: true)),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(
                for: ret,
                context: CaptureKeyRoutingContext(
                    meetingNotesModeVisible: true, meetingNotesIsWriting: true)),
            .consumeKey
        )
    }

    func testMeetingNotesModeMovesAndConsumesCommandChords() {
        let router = CaptureKeyCommandRouter()
        let base = CaptureKeyRoutingContext(meetingNotesModeVisible: true)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 125, characters: ""), context: base),
            .meetingNotesMoveNext
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 126, characters: ""), context: base),
            .meetingNotesMovePrevious
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 46, modifiers: .command, characters: "m"),
                context: base),
            .consumeKey
        )
    }
}
