import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureAliasCommandTests: XCTestCase {
    func testAliasEventRoutesAsCommandBackslashInEditorAndModalContexts() throws {
        let event = try XCTUnwrap(CapturePanelController.captureAliasKeyEvent(windowNumber: 0))
        XCTAssertEqual(event.type, .keyDown)
        XCTAssertEqual(event.keyCode, 42)
        XCTAssertEqual(event.modifierFlags, .command)
        XCTAssertEqual(event.characters, "\\")
        XCTAssertEqual(event.charactersIgnoringModifiers, "\\")

        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(router.command(for: event), .openTodayPomodoro)
        XCTAssertEqual(
            router.command(for: event, completionVisible: true),
            .openTodayPomodoro
        )

        let modalContexts = [
            CaptureKeyRoutingContext(stashPickerVisible: true, stashEntryCount: 1),
            CaptureKeyRoutingContext(templateShelfVisible: true, templateEntryCount: 1),
            CaptureKeyRoutingContext(taskIDPromptVisible: true),
            CaptureKeyRoutingContext(pomodoroNamePromptVisible: true),
            CaptureKeyRoutingContext(pullInChoiceVisible: true),
            CaptureKeyRoutingContext(inboxRouteChoiceVisible: true),
            CaptureKeyRoutingContext(pickerVisible: true),
        ]
        for context in modalContexts {
            XCTAssertEqual(router.command(for: event, context: context), .consumeKey)
        }
    }

    func testAliasPressDoesNotOpenPomodoroWhenControllerHasNeverShownPanel() {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)

        XCTAssertFalse(controller.routeCaptureAliasPress())
        XCTAssertFalse(model.todayPomodoroGotoInFlight)
    }
}
