import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureRecordInteractionTests: XCTestCase {
    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = ""
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
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    func testRecordCardTabNavigationAndSelection() {
        let router = CaptureKeyCommandRouter()
        let card = CaptureKeyRoutingContext(
            recordCardActive: true,
            recordAssistAvailable: true
        )

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48), context: card), .recordTab)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48, modifiers: .shift), context: card),
            .recordShiftTab
        )

        let list = CaptureKeyRoutingContext(
            recordCardActive: true,
            recordAssistAvailable: true,
            recordCompletionListVisible: true,
            completionVisible: true,
            completionHasSelection: false
        )
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48), context: list), .acceptCompletion)
    }

    func testRecordCardReturnWaitsOrAcceptsOnlyASelectedRow() {
        let router = CaptureKeyCommandRouter()
        let card = CaptureKeyRoutingContext(recordCardActive: true)

        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, characters: "\r"), context: card),
            .recordReturn(openAfterCapture: false)
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 36, modifiers: .control, characters: "\r"),
                context: card
            ),
            .recordReturn(openAfterCapture: true)
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 36, modifiers: .command, characters: "\r"),
                context: card
            ),
            .recordReturn(openAfterCapture: true)
        )

        let listWithoutSelection = CaptureKeyRoutingContext(
            recordCardActive: true,
            recordCompletionListVisible: true,
            completionVisible: true,
            completionHasSelection: false
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, characters: "\r"), context: listWithoutSelection),
            .recordReturn(openAfterCapture: false)
        )

        var selectedList = listWithoutSelection
        selectedList.completionHasSelection = true
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, characters: "\r"), context: selectedList),
            .acceptCompletion
        )
    }

    func testEscapeClosesCompletionBeforeRecordCard() {
        let router = CaptureKeyCommandRouter()
        let escape = keyEvent(keyCode: 53)
        XCTAssertEqual(
            router.command(
                for: escape,
                context: CaptureKeyRoutingContext(recordCardActive: true, completionVisible: true)
            ),
            .escape
        )
        XCTAssertEqual(
            router.command(for: escape, context: CaptureKeyRoutingContext(recordCardActive: true)),
            .escape
        )
    }

    func testNonRecordTabBehaviorRemainsUnchanged() {
        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48)), .tabEditorAssist)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48, modifiers: .shift)),
            .decreaseBulletIndentation
        )
    }
}
