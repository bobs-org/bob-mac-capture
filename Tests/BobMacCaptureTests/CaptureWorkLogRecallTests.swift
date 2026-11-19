import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Inline Work Log recall in the close-log completion popup: the popup opens
/// with no selection, Return keeps today's capture-as-typed behavior without
/// one, Tab takes the top row, and accepting a row replaces only the entry
/// summary. Fixtures are raw `bob capture-complete` `work_log` replies.
@MainActor
final class CaptureWorkLogRecallTests: XCTestCase {
    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func workLogResponse() throws -> CaptureCompletionResponse {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/capture-complete-work-log.json")
        return try JSONDecoder().decode(
            CaptureCompletionResponse.self, from: Data(contentsOf: url))
    }

    private func installWorkLogCompletion(
        on model: CapturePanelModel,
        draft: String,
        selectedIndex: Int?
    ) throws {
        model.plainDraft = draft
        model.completionResponse = try workLogResponse()
        model.selectedCompletionIndex = selectedIndex
    }

    func testWorkLogPopupKeepsSubmitWithoutSelection() {
        let router = CaptureKeyCommandRouter()
        let unselected = CaptureKeyRoutingContext(
            completionVisible: true,
            completionHasSelection: false
        )

        // Return with no selection captures the draft as typed.
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36), context: unselected), .submit)
        // Tab takes the top row when nothing is selected.
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48), context: unselected),
            .acceptCompletion)
        // Ctrl+N/P and the arrows cycle the popup from the top row.
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 125), context: unselected),
            .nextCompletion)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 126), context: unselected),
            .previousCompletion)
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 45, modifiers: .control), context: unselected),
            .nextCompletion)
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 35, modifiers: .control), context: unselected),
            .previousCompletion)
        // Esc closes the popup as it does today.
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 53), context: unselected), .escape)
    }

    func testWorkLogReturnAcceptsOnlyASelectedRow() {
        let router = CaptureKeyCommandRouter()
        let selected = CaptureKeyRoutingContext(
            completionVisible: true,
            completionHasSelection: true
        )

        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36), context: selected),
            .acceptCompletion)
    }

    func testWorkLogAcceptWithoutSelectionTakesTheTopRow() throws {
        let model = CapturePanelModel()
        try installWorkLogCompletion(on: model, draft: "x auth", selectedIndex: nil)

        XCTAssertTrue(model.acceptSelectedCompletion())

        XCTAssertEqual(model.plainDraft, "x auth retry")
        XCTAssertNil(model.completionResponse)
    }

    func testWorkLogAcceptReplacesOnlyTheEntrySummary() throws {
        let model = CapturePanelModel()
        try installWorkLogCompletion(on: model, draft: "x auth", selectedIndex: 1)

        XCTAssertTrue(model.acceptSelectedCompletion())

        // The replacement covers only the summary span, so the close token
        // and any index token survive the splice.
        XCTAssertEqual(model.plainDraft, "x auth timeout recovery")
        XCTAssertNil(model.completionResponse)
    }

    func testWorkLogAcceptKeepsIndexTokensOutsideTheSummary() throws {
        let model = CapturePanelModel()
        let base = try workLogResponse()
        let response = CaptureCompletionResponse(
            ok: base.ok,
            cursor: 10,
            replacement: CaptureRange(start: 6, end: 10),
            context: base.context,
            candidates: base.candidates,
            initialSelection: base.initialSelection,
            query: base.query
        )
        model.plainDraft = "x\n- 1 auth"
        model.completionResponse = response
        model.selectedCompletionIndex = 0

        XCTAssertTrue(model.acceptSelectedCompletion())

        XCTAssertEqual(model.plainDraft, "x\n- 1 auth retry")
    }
}
